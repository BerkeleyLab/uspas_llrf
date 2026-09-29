"""Plotly Dash web application for live LLRF waveform monitoring and control.
Interacts with LLRFApp APIs to display live time series waveforms from:
- get_raw_bufs_df()
- get_iq_wfms_df()
- get_cic_wfm_df()
"""

import time
import logging
import numpy as np
import dash
from dash import dcc, html, dash_table, Input, Output, State
import plotly.graph_objs as go
from plotly.subplots import make_subplots

from uspas_llrf.app.app import LLRFApp
from uspas_llrf.model.llrf_shell import DacDriveSel

logger = logging.getLogger(__name__)

# dac_drive_sel mux in llrf_shell.v: which loop's I/Q lands on DAC A / DAC B
DAC_DRIVE_OPTIONS = [
    {'label': ' I0Q0 (loop0 drives)', 'value': int(DacDriveSel.I0Q0)},
    {'label': ' I1Q1 (loop1 drives)', 'value': int(DacDriveSel.I1Q1)},
    {'label': ' I0I1 (dual loops, I)', 'value': int(DacDriveSel.I0I1)},
    {'label': ' Q0Q1 (dual loops, Q)', 'value': int(DacDriveSel.Q0Q1)},
]


def format_bsp_records(bsp_info):
    """Flatten a decoded MarbleDevInfo into rows for a DataTable.

    Mirrors MarbleDevInfo.format_marble_info / format_zest_status, but
    returns a list of dicts with keys Category / Component / Parameter / Value.
    """
    records = []
    if bsp_info is None or getattr(bsp_info, 'data', None) is None:
        return records
    d = bsp_info.data[0]
    m = d['marble_info']
    z = d['zest_status']

    def _s(b):
        return b.decode(errors='ignore').strip()

    var_code = int(m['marble_variant'])
    records.append({
        'Category': 'Marble', 'Component': 'Carrier',
        'Parameter': 'Variant',
        'Value': bsp_info.marble_var.get(var_code, f'Unknown ({var_code})')
    })

    adn = m['adn4600']
    routes = [f"IN {adn['xpt_status'][i]} -> OUT {i}" for i in range(4)]
    records.append({
        'Category': 'Marble', 'Component': f"ADN4600 {_s(adn['refdes'])}",
        'Parameter': 'Crosspoint', 'Value': ', '.join(routes)
    })

    for ix in range(3):
        ina = m['ina219'][ix]
        records.append({
            'Category': 'Marble',
            'Component': f"INA219 {_s(ina['refdes'])} {_s(ina['name'])}",
            'Parameter': 'Vbus / Current / Power / Vshunt',
            'Value': (f"{ina['vbus'] / 1e3:.2f} V | "
                      f"{ina['current'] / 1e3:.1f} mA | "
                      f"{ina['power'] / 1e3:.1f} mW | "
                      f"{ina['vshunt'] / 1e3:.2f} mV")
        })

    for ix in range(2):
        pca = m['pca9555'][ix]
        records.append({
            'Category': 'Marble',
            'Component': f"PCA9555 {_s(pca['refdes'])} {_s(pca['name'])}",
            'Parameter': 'I0 / I1',
            'Value': f"{pca['i0_val']:08b} | {pca['i1_val']:08b}"
        })

    for ix in range(2):
        q = m['qsfp'][ix]
        if q['module_present']:
            val = (f"{_s(q['vendor_name'])} PN {_s(q['part_num'])} "
                   f"SN {_s(q['serial_num'])} | "
                   f"{q['temperature']} C | {q['voltage']} mV | "
                   f"LOS {q['chan_stat_los']:08b}")
        else:
            val = 'Not present'
        records.append({
            'Category': 'Marble', 'Component': f'QSFP {ix + 1}',
            'Parameter': 'Module', 'Value': val
        })

    si = m['si570']
    records.append({
        'Category': 'Marble', 'Component': 'SI570',
        'Parameter': 'f_out / f_reset / f_xtal / HSDIV / N1',
        'Value': (f"{si['f_out_hz'] / 1e6:.3f} MHz | "
                  f"{si['f_reset_hz'] / 1e6:.3f} MHz | "
                  f"{si['f_xtal_hz'] / 1e6:.3f} MHz | "
                  f"{si['hs_div']} | {si['n1']}")
    })

    for ix in range(4):
        freq = z['zest_frequencies'][ix] * 125 / (1 << 16)
        val = f"{freq:.3f} MHz"
        if ix < 3:
            val += f" | {z['zest_phases'][ix] / (1 << 16):.3f} UI"
        records.append({
            'Category': 'Zest',
            'Component': bsp_info.zest_fcnt_names.get(ix, f'CLK{ix}'),
            'Parameter': 'Freq / Phase', 'Value': val
        })

    amc = np.bitwise_and(z['amc7823_adcs'], 0xfff)
    records.append({
        'Category': 'Zest', 'Component': 'AMC7823',
        'Parameter': 'Voltage [0..7]',
        'Value': ', '.join(f"{v * 2.5 / 0xfff:.3f} V" for v in amc[:8])
    })
    records.append({
        'Category': 'Zest', 'Component': 'AMC7823',
        'Parameter': 'Temperature',
        'Value': f"{amc[8] * 2.6 * 0.61 - 273:.2f} C"
    })
    records.append({
        'Category': 'Zest', 'Component': 'AD7794',
        'Parameter': 'Voltage [0..5]',
        'Value': ', '.join(f"{v * 1.17 / 0xffffff:.3f} V"
                           for v in z['ad7794_adcs'])
    })
    return records


def create_dash_app(llrf_app: LLRFApp) -> dash.Dash:
    """Create and configure a Plotly Dash application for an LLRFApp instance.

    Args:
        llrf_app (LLRFApp): Connected LLRFApp hardware device interface.

    Returns:
        dash.Dash: Configured Dash application.
    """
    app = dash.Dash(__name__, title=f"LLRF Live - {llrf_app.app_name}")

    # Pulse start/length registers count dsp_clk cycles; the UI works in ns.
    # Slider step is one clk period so every position is an exact clk count.
    t_clk_ns = llrf_app.config['DSP_CLK_CYCLE']
    pulse_max_ns = 20000
    pulse_marks = {v: f'{v // 1000} µs' for v in range(0, pulse_max_ns + 1, 5000)}

    def ns_to_clk(ns):
        return int(round(ns / t_clk_ns))

    # Seed the DAC drive radio from hardware so the UI reflects current state
    try:
        dac_drive_sel_init = int(llrf_app.read_reg('dac_drive_sel'))
    except Exception as e:
        logger.warning(f"Could not read dac_drive_sel, defaulting to 0: {e}")
        dac_drive_sel_init = int(DacDriveSel.I0Q0)

    def pulse_slider(id_, value_clk):
        return dcc.Slider(
            id=id_, min=0, max=pulse_max_ns, step=t_clk_ns,
            value=value_clk * t_clk_ns, marks=pulse_marks,
            tooltip={'placement': 'bottom', 'always_visible': True},
            updatemode='mouseup'
        )

    app.layout = html.Div(
        style={
            'fontFamily': 'Arial, sans-serif',
            'margin': '20px',
            'backgroundColor': '#f7f9fa',
            'padding': '20px',
            'borderRadius': '8px'
        },
        children=[
            html.Div(
                style={
                    'display': 'flex',
                    'justifyContent': 'space-between',
                    'alignItems': 'center',
                    'marginBottom': '15px'
                },
                children=[
                    html.H2(
                        f"LLRF Live Monitor & Control: {llrf_app.app_name}",
                        style={'color': '#2c3e50', 'margin': '0'}
                    ),
                    html.Div(
                        style={'display': 'flex', 'gap': '10px',
                               'alignItems': 'center'},
                        children=[
                            html.Div([
                                html.Label(
                                    "DAC Drive Select:",
                                    style={'fontSize': '11px',
                                           'fontWeight': 'bold',
                                           'display': 'block'}
                                ),
                                dcc.RadioItems(
                                    id='dac-drive-sel',
                                    options=DAC_DRIVE_OPTIONS,
                                    value=dac_drive_sel_init,
                                    inline=True,
                                    style={'fontSize': '12px'}
                                ),
                                html.Div(
                                    id='dac-drive-status',
                                    style={'fontSize': '11px',
                                           'color': '#7f8c8d'}
                                )
                            ], style={'marginRight': '20px'}),
                            html.Button(
                                'Initialize Loopback Demo',
                                id='init-loopback-btn',
                                n_clicks=0,
                                style={
                                    'backgroundColor': '#27ae60',
                                    'color': 'white',
                                    'border': 'none',
                                    'padding': '8px 16px',
                                    'borderRadius': '4px',
                                    'cursor': 'pointer',
                                    'fontWeight': 'bold'
                                }
                            ),
                            html.Div(
                                id='init-status',
                                style={
                                    'fontSize': '12px',
                                    'color': '#27ae60',
                                    'fontWeight': 'bold'
                                }
                            )
                        ]
                    )
                ]
            ),
            html.Div(
                style={
                    'display': 'flex',
                    'flexWrap': 'wrap',
                    'gap': '15px',
                    'marginBottom': '20px'
                },
                children=[
                    # Loop0 Controller Box
                    html.Div(
                        style={
                            'flex': '1',
                            'minWidth': '420px',
                            'backgroundColor': '#ffffff',
                            'padding': '15px',
                            'borderRadius': '6px',
                            'boxShadow': '0 2px 4px rgba(0,0,0,0.05)'
                        },
                        children=[
                            html.Div(
                                style={'display': 'flex',
                                       'justifyContent': 'space-between',
                                       'alignItems': 'center',
                                       'marginBottom': '10px'},
                                children=[
                                    html.H4("Loop 0 Controller",
                                            style={'margin': '0',
                                                   'color': '#2c3e50'}),
                                    html.Div(
                                        style={'display': 'flex',
                                               'gap': '8px'},
                                        children=[
                                            html.Button(
                                                'Open Loop',
                                                id='loop0-open-btn',
                                                n_clicks=0,
                                                style={
                                                    'backgroundColor': '#e74c3c',
                                                    'color': 'white',
                                                    'border': 'none',
                                                    'padding': '4px 10px',
                                                    'borderRadius': '4px',
                                                    'cursor': 'pointer',
                                                    'fontSize': '12px',
                                                    'fontWeight': 'bold'
                                                }
                                            ),
                                            html.Button(
                                                'Close Loop',
                                                id='loop0-close-btn',
                                                n_clicks=0,
                                                style={
                                                    'backgroundColor': '#27ae60',
                                                    'color': 'white',
                                                    'border': 'none',
                                                    'padding': '4px 10px',
                                                    'borderRadius': '4px',
                                                    'cursor': 'pointer',
                                                    'fontSize': '12px',
                                                    'fontWeight': 'bold'
                                                }
                                            )
                                        ]
                                    )
                                ]
                            ),
                            html.Div(
                                style={'display': 'grid',
                                       'gridTemplateColumns': 'repeat(2, 1fr)',
                                       'gap': '10px', 'marginBottom': '12px'},
                                children=[
                                    html.Div([
                                        html.Label("Amp Setpoint [cnt]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-amp-setp',
                                                  type='number',
                                                  value=20000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Phs Setpoint [cnt/raw]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-phs-setp',
                                                  type='number',
                                                  value=0,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Kp Amp:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-kp-amp',
                                                  type='number',
                                                  value=1000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Ki Amp:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-ki-amp',
                                                  type='number',
                                                  value=100,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Kp Phs:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-kp-phs',
                                                  type='number',
                                                  value=1000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Ki Phs:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop0-ki-phs',
                                                  type='number',
                                                  value=100,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ])
                                ]
                            ),
                            html.Hr(style={'borderColor': '#ecf0f1',
                                           'margin': '8px 0'}),
                            html.Div(
                                style={'display': 'grid',
                                       'gridTemplateColumns': 'auto 1fr 1fr',
                                       'gap': '10px',
                                       'alignItems': 'center'},
                                children=[
                                    html.Div([
                                        html.Label("Pulse Mode:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold',
                                                          'display': 'block'}),
                                        dcc.Checklist(
                                            id='loop0-pulse-enable',
                                            options=[{'label': ' Enable',
                                                      'value': 'en'}],
                                            value=[]
                                        )
                                    ]),
                                    html.Div([
                                        html.Label("Pulse Start [ns]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        pulse_slider('loop0-pulse-start', 0)
                                    ]),
                                    html.Div([
                                        html.Label("Pulse Length [ns]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        pulse_slider('loop0-pulse-len', 10)
                                    ])
                                ]
                            ),
                            html.Div(id='loop0-status-msg',
                                     style={'fontSize': '12px', 'color': '#2980b9',
                                            'marginTop': '6px', 'fontWeight': 'bold'})
                        ]
                    ),
                    # Loop1 Controller Box
                    html.Div(
                        style={
                            'flex': '1',
                            'minWidth': '420px',
                            'backgroundColor': '#ffffff',
                            'padding': '15px',
                            'borderRadius': '6px',
                            'boxShadow': '0 2px 4px rgba(0,0,0,0.05)'
                        },
                        children=[
                            html.Div(
                                style={'display': 'flex',
                                       'justifyContent': 'space-between',
                                       'alignItems': 'center',
                                       'marginBottom': '10px'},
                                children=[
                                    html.H4("Loop 1 Controller",
                                            style={'margin': '0',
                                                   'color': '#2c3e50'}),
                                    html.Div(
                                        style={'display': 'flex',
                                               'gap': '8px'},
                                        children=[
                                            html.Button(
                                                'Open Loop',
                                                id='loop1-open-btn',
                                                n_clicks=0,
                                                style={
                                                    'backgroundColor': '#e74c3c',
                                                    'color': 'white',
                                                    'border': 'none',
                                                    'padding': '4px 10px',
                                                    'borderRadius': '4px',
                                                    'cursor': 'pointer',
                                                    'fontSize': '12px',
                                                    'fontWeight': 'bold'
                                                }
                                            ),
                                            html.Button(
                                                'Close Loop',
                                                id='loop1-close-btn',
                                                n_clicks=0,
                                                style={
                                                    'backgroundColor': '#27ae60',
                                                    'color': 'white',
                                                    'border': 'none',
                                                    'padding': '4px 10px',
                                                    'borderRadius': '4px',
                                                    'cursor': 'pointer',
                                                    'fontSize': '12px',
                                                    'fontWeight': 'bold'
                                                }
                                            )
                                        ]
                                    )
                                ]
                            ),
                            html.Div(
                                style={'display': 'grid',
                                       'gridTemplateColumns': 'repeat(2, 1fr)',
                                       'gap': '10px', 'marginBottom': '12px'},
                                children=[
                                    html.Div([
                                        html.Label("Amp Setpoint [cnt]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-amp-setp',
                                                  type='number',
                                                  value=20000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Phs Setpoint [cnt/raw]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-phs-setp',
                                                  type='number',
                                                  value=0,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Kp Amp:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-kp-amp',
                                                  type='number',
                                                  value=1000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Ki Amp:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-ki-amp',
                                                  type='number',
                                                  value=100,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Kp Phs:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-kp-phs',
                                                  type='number',
                                                  value=1000,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ]),
                                    html.Div([
                                        html.Label("Ki Phs:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        dcc.Input(id='loop1-ki-phs',
                                                  type='number',
                                                  value=100,
                                                  debounce=True,
                                                  style={'width': '90%'})
                                    ])
                                ]
                            ),
                            html.Hr(style={'borderColor': '#ecf0f1',
                                           'margin': '8px 0'}),
                            html.Div(
                                style={'display': 'grid',
                                       'gridTemplateColumns': 'auto 1fr 1fr',
                                       'gap': '10px',
                                       'alignItems': 'center'},
                                children=[
                                    html.Div([
                                        html.Label("Pulse Mode:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold',
                                                          'display': 'block'}),
                                        dcc.Checklist(
                                            id='loop1-pulse-enable',
                                            options=[{'label': ' Enable',
                                                      'value': 'en'}],
                                            value=[]
                                        )
                                    ]),
                                    html.Div([
                                        html.Label("Pulse Start [ns]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        pulse_slider('loop1-pulse-start', 0)
                                    ]),
                                    html.Div([
                                        html.Label("Pulse Length [ns]:",
                                                   style={'fontSize': '11px',
                                                          'fontWeight': 'bold'}),
                                        pulse_slider('loop1-pulse-len', 10)
                                    ])
                                ]
                            ),
                            html.Div(id='loop1-status-msg',
                                     style={'fontSize': '12px', 'color': '#2980b9',
                                            'marginTop': '6px', 'fontWeight': 'bold'})
                        ]
                    )
                ]
            ),
            html.Div(
                style={
                    'display': 'flex',
                    'flexWrap': 'wrap',
                    'gap': '15px',
                    'alignItems': 'center',
                    'marginBottom': '20px',
                    'backgroundColor': '#ffffff',
                    'padding': '15px',
                    'borderRadius': '6px',
                    'boxShadow': '0 2px 4px rgba(0,0,0,0.05)'
                },
                children=[
                    html.Div([
                        html.Label(
                            "Data Source:",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        dcc.RadioItems(
                            id='wfm-source-select',
                            options=[
                                {'label': ' Raw ADC (get_raw_bufs_df) ',
                                 'value': 'raw'},
                                {'label': ' Baseband IQ (get_iq_wfms_df) ',
                                 'value': 'iq'},
                                {'label': ' CIC Decimated (get_cic_wfm_df) ',
                                 'value': 'cic'}
                            ],
                            value='cic',
                            inline=True
                        )
                    ]),
                    html.Div([
                        html.Label(
                            "Plot Mode:",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        dcc.RadioItems(
                            id='plot-mode-select',
                            options=[
                                {'label': ' Amp & Phs ', 'value': 'amp_phs'},
                                {'label': ' Amplitude only ',
                                 'value': 'amp_only'}
                            ],
                            value='amp_phs',
                            inline=True
                        )
                    ]),
                    html.Div([
                        html.Label(
                            "Signals:",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        dcc.Dropdown(
                            id='signal-select',
                            multi=True,
                            style={'minWidth': '220px'}
                        )
                    ]),
                    html.Div([
                        html.Label(
                            "Auto Refresh:",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        dcc.Checklist(
                            id='auto-refresh-check',
                            options=[{'label': ' Enabled', 'value': 'on'}],
                            value=['on']
                        )
                    ]),
                    html.Div([
                        html.Label(
                            "Interval (ms):",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        dcc.Input(
                            id='refresh-interval-input',
                            type='number',
                            value=1000,
                            min=200,
                            step=100,
                            style={'width': '100px'}
                        )
                    ]),
                    html.Div([
                        html.Button(
                            'Fetch Once',
                            id='fetch-btn',
                            n_clicks=0,
                            style={
                                'marginTop': '18px',
                                'padding': '6px 14px',
                                'cursor': 'pointer'
                            }
                        )
                    ])
                ]
            ),
            dcc.Graph(id='wfm-graph', style={'height': '550px'}),
            html.Div(
                style={
                    'marginTop': '25px',
                    'backgroundColor': '#ffffff',
                    'padding': '15px',
                    'borderRadius': '6px',
                    'boxShadow': '0 2px 4px rgba(0,0,0,0.05)'
                },
                children=[
                    html.H3(
                        "RF Monitor Snapshot (get_rfmon)",
                        style={'color': '#2c3e50', 'marginTop': '0',
                               'marginBottom': '10px'}
                    ),
                    dash_table.DataTable(
                        id='rfmon-table',
                        columns=[
                            {'name': 'Channel', 'id': 'Channel'},
                            {'name': 'mon_amp', 'id': 'mon_amp'},
                            {'name': 'mon_phs', 'id': 'mon_phs'},
                            {'name': 'Amp [cnt]', 'id': 'Amp [cnt]'},
                            {'name': 'Phs [deg]', 'id': 'Phs [deg]'}
                        ],
                        data=[],
                        style_table={'overflowX': 'auto'},
                        style_header={
                            'backgroundColor': '#34495e',
                            'color': 'white',
                            'fontWeight': 'bold',
                            'textAlign': 'center'
                        },
                        style_cell={
                            'textAlign': 'center',
                            'padding': '8px',
                            'fontSize': '13px'
                        },
                        style_data_conditional=[
                            {
                                'if': {'row_index': 'odd'},
                                'backgroundColor': '#f8f9fa'
                            }
                        ]
                    )
                ]
            ),
            html.Div(
                style={
                    'marginTop': '25px',
                    'backgroundColor': '#ffffff',
                    'padding': '15px',
                    'borderRadius': '6px',
                    'boxShadow': '0 2px 4px rgba(0,0,0,0.05)'
                },
                children=[
                    html.Div(
                        style={'display': 'flex',
                               'justifyContent': 'space-between',
                               'alignItems': 'center',
                               'marginBottom': '10px'},
                        children=[
                            html.H3(
                                "Board Support Info (get_bsp_info)",
                                style={'color': '#2c3e50', 'margin': '0'}
                            ),
                            html.Div(
                                style={'display': 'flex', 'gap': '10px',
                                       'alignItems': 'center'},
                                children=[
                                    html.Div(
                                        id='bsp-status',
                                        style={'fontSize': '12px',
                                               'color': '#7f8c8d'}
                                    ),
                                    html.Button(
                                        'Refresh BSP',
                                        id='bsp-refresh-btn',
                                        n_clicks=0,
                                        style={'padding': '6px 14px',
                                               'cursor': 'pointer'}
                                    )
                                ]
                            )
                        ]
                    ),
                    dash_table.DataTable(
                        id='bsp-table',
                        columns=[
                            {'name': 'Category', 'id': 'Category'},
                            {'name': 'Component', 'id': 'Component'},
                            {'name': 'Parameter', 'id': 'Parameter'},
                            {'name': 'Value', 'id': 'Value'}
                        ],
                        data=[],
                        style_table={'overflowX': 'auto'},
                        style_header={
                            'backgroundColor': '#34495e',
                            'color': 'white',
                            'fontWeight': 'bold',
                            'textAlign': 'left'
                        },
                        style_cell={
                            'textAlign': 'left',
                            'padding': '6px 8px',
                            'fontSize': '13px',
                            'whiteSpace': 'normal',
                            'height': 'auto'
                        },
                        style_cell_conditional=[
                            {'if': {'column_id': 'Value'},
                             'fontFamily': 'monospace'}
                        ],
                        style_data_conditional=[
                            {
                                'if': {'row_index': 'odd'},
                                'backgroundColor': '#f8f9fa'
                            }
                        ]
                    )
                ]
            ),
            dcc.Interval(
                id='live-interval',
                interval=1000,
                n_intervals=0
            ),
            html.Div(
                id='status-text',
                style={
                    'marginTop': '10px',
                    'color': '#7f8c8d',
                    'fontSize': '13px'
                }
            )
        ]
    )

    @app.callback(
        Output('bsp-table', 'data'),
        Output('bsp-status', 'children'),
        Input('bsp-refresh-btn', 'n_clicks')
    )
    def update_bsp_table(_n_clicks):
        # Fires once on page load and on every button click.
        try:
            info = llrf_app.get_bsp_info()
            rows = format_bsp_records(info)
            return rows, f"Read at {time.strftime('%H:%M:%S')}"
        except Exception as e:
            logger.error(f"Error reading BSP info: {e}")
            return [], f"BSP read failed: {e}"

    @app.callback(
        Output('dac-drive-status', 'children'),
        Input('dac-drive-sel', 'value'),
        prevent_initial_call=True
    )
    def set_dac_drive_sel(value):
        if value is None:
            return ""
        try:
            llrf_app.dac_drive_sel = int(value)
            name = DacDriveSel(int(value)).name
            return f"dac_drive_sel={name} ({int(value)}) at {time.strftime('%H:%M:%S')}"
        except Exception as e:
            return f"dac_drive_sel write failed: {e}"

    @app.callback(
        Output('init-status', 'children'),
        Input('init-loopback-btn', 'n_clicks'),
        prevent_initial_call=True
    )
    def init_loopback_demo(n_clicks):
        if n_clicks and n_clicks > 0:
            try:
                llrf_app.init_cw_demo()
                llrf_app.init_loop('loop0', amp_setp_adc=2e4)
                llrf_app.init_loop('loop1', amp_setp_adc=2e4)
                return f"Demo initialized ({time.strftime('%H:%M:%S')})"
            except Exception as e:
                return f"Init failed: {e}"
        return ""

    @app.callback(
        Output('loop0-status-msg', 'children'),
        Input('loop0-open-btn', 'n_clicks'),
        Input('loop0-close-btn', 'n_clicks'),
        Input('loop0-amp-setp', 'value'),
        Input('loop0-phs-setp', 'value'),
        Input('loop0-kp-amp', 'value'),
        Input('loop0-ki-amp', 'value'),
        Input('loop0-kp-phs', 'value'),
        Input('loop0-ki-phs', 'value'),
        Input('loop0-pulse-enable', 'value'),
        Input('loop0-pulse-start', 'value'),
        Input('loop0-pulse-len', 'value'),
        prevent_initial_call=True
    )
    def control_loop0(open_clicks, close_clicks,
                      amp_setp, phs_setp,
                      kp_amp, ki_amp, kp_phs, ki_phs,
                      en0_val, start0_val, len0_val):
        ctx = dash.callback_context
        if not ctx.triggered:
            return ""
        prop_id = ctx.triggered[0]['prop_id']
        trig_id = prop_id.split('.')[0]

        try:
            if trig_id == 'loop0-open-btn':
                llrf_app.open_loop('loop0')
                return f"Loop0 OPENED at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-close-btn':
                llrf_app.close_loop('loop0')
                return f"Loop0 CLOSED at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-amp-setp' and amp_setp is not None:
                llrf_app.write_reg('loop0_amp_setpoint', int(amp_setp))
                return f"Wrote loop0_amp_setpoint={amp_setp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-phs-setp' and phs_setp is not None:
                llrf_app.write_reg('loop0_phs_setpoint', int(phs_setp))
                return f"Wrote loop0_phs_setpoint={phs_setp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-kp-amp' and kp_amp is not None:
                llrf_app.write_reg('loop0_Kp_amp', int(kp_amp))
                return f"Wrote loop0_Kp_amp={kp_amp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-ki-amp' and ki_amp is not None:
                llrf_app.write_reg('loop0_Ki_amp', int(ki_amp))
                return f"Wrote loop0_Ki_amp={ki_amp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-kp-phs' and kp_phs is not None:
                llrf_app.write_reg('loop0_Kp_phs', int(kp_phs))
                return f"Wrote loop0_Kp_phs={kp_phs} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-ki-phs' and ki_phs is not None:
                llrf_app.write_reg('loop0_Ki_phs', int(ki_phs))
                return f"Wrote loop0_Ki_phs={ki_phs} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-pulse-enable':
                en0 = 'en' in (en0_val or [])
                curr_modes = int(llrf_app.read_reg('pulse_modes'))
                pulse_modes = (curr_modes | 0b01) if en0 else (curr_modes & ~0b01)
                llrf_app.write_reg('pulse_modes', pulse_modes)
                mode_str = "ENABLED" if en0 else "DISABLED"
                return f"Loop0 pulse mode {mode_str} (pulse_modes={bin(pulse_modes)}) at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-pulse-start' and start0_val is not None:
                clk = ns_to_clk(start0_val)
                llrf_app.write_reg('loop0_pulse_start', clk)
                return f"Wrote loop0_pulse_start={clk} clk ({start0_val:.1f} ns) at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop0-pulse-len' and len0_val is not None:
                clk = ns_to_clk(len0_val)
                llrf_app.write_reg('loop0_pulse_high_len', clk)
                return f"Wrote loop0_pulse_high_len={clk} clk ({len0_val:.1f} ns) at {time.strftime('%H:%M:%S')}"
        except Exception as e:
            return f"Loop0 error: {e}"
        return ""

    @app.callback(
        Output('loop1-status-msg', 'children'),
        Input('loop1-open-btn', 'n_clicks'),
        Input('loop1-close-btn', 'n_clicks'),
        Input('loop1-amp-setp', 'value'),
        Input('loop1-phs-setp', 'value'),
        Input('loop1-kp-amp', 'value'),
        Input('loop1-ki-amp', 'value'),
        Input('loop1-kp-phs', 'value'),
        Input('loop1-ki-phs', 'value'),
        Input('loop1-pulse-enable', 'value'),
        Input('loop1-pulse-start', 'value'),
        Input('loop1-pulse-len', 'value'),
        prevent_initial_call=True
    )
    def control_loop1(open_clicks, close_clicks,
                      amp_setp, phs_setp,
                      kp_amp, ki_amp, kp_phs, ki_phs,
                      en1_val, start1_val, len1_val):
        ctx = dash.callback_context
        if not ctx.triggered:
            return ""
        prop_id = ctx.triggered[0]['prop_id']
        trig_id = prop_id.split('.')[0]

        try:
            if trig_id == 'loop1-open-btn':
                llrf_app.open_loop('loop1')
                return f"Loop1 OPENED at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-close-btn':
                llrf_app.close_loop('loop1')
                return f"Loop1 CLOSED at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-amp-setp' and amp_setp is not None:
                llrf_app.write_reg('loop1_amp_setpoint', int(amp_setp))
                return f"Wrote loop1_amp_setpoint={amp_setp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-phs-setp' and phs_setp is not None:
                llrf_app.write_reg('loop1_phs_setpoint', int(phs_setp))
                return f"Wrote loop1_phs_setpoint={phs_setp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-kp-amp' and kp_amp is not None:
                llrf_app.write_reg('loop1_Kp_amp', int(kp_amp))
                return f"Wrote loop1_Kp_amp={kp_amp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-ki-amp' and ki_amp is not None:
                llrf_app.write_reg('loop1_Ki_amp', int(ki_amp))
                return f"Wrote loop1_Ki_amp={ki_amp} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-kp-phs' and kp_phs is not None:
                llrf_app.write_reg('loop1_Kp_phs', int(kp_phs))
                return f"Wrote loop1_Kp_phs={kp_phs} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-ki-phs' and ki_phs is not None:
                llrf_app.write_reg('loop1_Ki_phs', int(ki_phs))
                return f"Wrote loop1_Ki_phs={ki_phs} at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-pulse-enable':
                en1 = 'en' in (en1_val or [])
                curr_modes = int(llrf_app.read_reg('pulse_modes'))
                pulse_modes = (curr_modes | 0b10) if en1 else (curr_modes & ~0b10)
                llrf_app.write_reg('pulse_modes', pulse_modes)
                mode_str = "ENABLED" if en1 else "DISABLED"
                return f"Loop1 pulse mode {mode_str} (pulse_modes={bin(pulse_modes)}) at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-pulse-start' and start1_val is not None:
                clk = ns_to_clk(start1_val)
                llrf_app.write_reg('loop1_pulse_start', clk)
                return f"Wrote loop1_pulse_start={clk} clk ({start1_val:.1f} ns) at {time.strftime('%H:%M:%S')}"
            elif trig_id == 'loop1-pulse-len' and len1_val is not None:
                clk = ns_to_clk(len1_val)
                llrf_app.write_reg('loop1_pulse_high_len', clk)
                return f"Wrote loop1_pulse_high_len={clk} clk ({len1_val:.1f} ns) at {time.strftime('%H:%M:%S')}"
        except Exception as e:
            return f"Loop1 error: {e}"
        return ""

    @app.callback(
        [Output('signal-select', 'options'),
         Output('signal-select', 'value')],
        [Input('wfm-source-select', 'value')]
    )
    def update_signal_options(source):
        if source == 'raw':
            sigs = llrf_app.signals[:llrf_app.n_adc]
            default_sigs = sigs[:2]
        elif source == 'iq':
            sigs = llrf_app.signals
            default_sigs = [sigs[0], sigs[1]] if len(sigs) >= 2 else sigs
        else:  # 'cic'
            sigs = llrf_app.cic_names
            default_sigs = sigs[:2] if len(sigs) >= 2 else sigs

        options = [{'label': s, 'value': s} for s in sigs]
        return options, default_sigs

    @app.callback(
        Output('live-interval', 'disabled'),
        Output('live-interval', 'interval'),
        Input('auto-refresh-check', 'value'),
        Input('refresh-interval-input', 'value')
    )
    def config_interval(auto_check, interval_ms):
        disabled = 'on' not in (auto_check or [])
        interval = (
            interval_ms if interval_ms and interval_ms >= 100 else 1000
        )
        return disabled, interval

    @app.callback(
        Output('wfm-graph', 'figure'),
        Output('rfmon-table', 'data'),
        Output('status-text', 'children'),
        Input('live-interval', 'n_intervals'),
        Input('fetch-btn', 'n_clicks'),
        State('wfm-source-select', 'value'),
        State('plot-mode-select', 'value'),
        State('signal-select', 'value')
    )
    def update_plot_and_rfmon(_n_intervals, _n_clicks, source, plot_mode,
                              selected_sigs):
        # 1. Update RF Monitor Table
        rfmon_data = []
        try:
            df_rfmon = llrf_app.get_rfmon()
            df_rfmon_reset = df_rfmon.reset_index().rename(
                columns={'index': 'Channel'})
            for col in ['Amp [cnt]', 'Phs [deg]']:
                if col in df_rfmon_reset.columns:
                    df_rfmon_reset[col] = df_rfmon_reset[col].map(
                        lambda v: f"{v:.3f}" if isinstance(
                            v, (int, float)) else str(v)
                    )
            rfmon_data = df_rfmon_reset.to_dict('records')
        except Exception as e:
            logger.error(f"Error fetching RF monitor data: {e}")

        # 2. Update Waveforms Plot
        try:
            if source == 'raw':
                df = llrf_app.get_raw_bufs_df()
            elif source == 'iq':
                df = llrf_app.get_iq_wfms_df()
            else:  # 'cic'
                df = llrf_app.get_cic_wfm_df()
        except Exception as e:
            empty_fig = go.Figure()
            empty_fig.update_layout(
                title=f"Error reading hardware waveform: {e}"
            )
            return empty_fig, rfmon_data, f"Error: {e}"

        fig = go.Figure()
        selected = selected_sigs or []

        if source == 'raw':
            cols_to_plot = [c for c in selected if c in df.columns]
            if not cols_to_plot:
                cols_to_plot = [
                    c for c in df.columns
                    if not c.endswith(('_amp', '_phs'))
                ]
            for col in cols_to_plot:
                fig.add_trace(go.Scatter(
                    x=df.index,
                    y=df[col],
                    mode='lines',
                    name=col
                ))
            fig.update_layout(
                title=f"{source.upper()} Waveforms",
                xaxis_title="Time [ns]",
                yaxis_title="ADC Counts"
            )
        elif plot_mode == 'amp_only':
            for s in selected:
                amp_col = f"{s}_amp" if f"{s}_amp" in df.columns else s
                if amp_col in df.columns:
                    fig.add_trace(go.Scatter(
                        x=df.index,
                        y=df[amp_col],
                        mode='lines',
                        name=f"{s} Amp"
                    ))
            fig.update_layout(
                title=f"{source.upper()} Waveform Amplitudes",
                xaxis_title="Time [ns]",
                yaxis_title="Amplitude [ADC cnt]"
            )
        else:  # 'amp_phs'
            fig = make_subplots(
                rows=2, cols=1,
                shared_xaxes=True,
                vertical_spacing=0.08,
                subplot_titles=("Amplitude [ADC cnt]", "Phase [deg]")
            )
            for s in selected:
                amp_col = f"{s}_amp" if f"{s}_amp" in df.columns else s
                phs_col = f"{s}_phs" if f"{s}_phs" in df.columns else None

                if amp_col in df.columns:
                    fig.add_trace(go.Scatter(
                        x=df.index,
                        y=df[amp_col],
                        mode='lines',
                        name=f"{s} Amp"
                    ), row=1, col=1)

                if phs_col and phs_col in df.columns:
                    fig.add_trace(go.Scatter(
                        x=df.index,
                        y=df[phs_col],
                        mode='lines',
                        name=f"{s} Phs"
                    ), row=2, col=1)

            fig.update_layout(
                title=f"{source.upper()} Amplitude & Phase Waveforms",
                xaxis2_title="Time [ns]"
            )

        fig.update_layout(
            template='plotly_white',
            margin=dict(l=50, r=30, t=50, b=40),
            legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0)
        )

        status = (
            f"Updated at {time.strftime('%H:%M:%S')} | "
            f"Source: {source} | Samples: {len(df)} | "
            f"Duration: {df.index[-1]:.1f} ns"
        )
        return fig, rfmon_data, status

    return app


def run_dash(llrf_app: LLRFApp, host='0.0.0.0', port=8050,
             debug=False, **kwargs):
    """Launch the Dash live monitoring web application.

    Args:
        llrf_app (LLRFApp): Connected LLRFApp instance.
        host (str): Dash server host IP.
        port (int): Dash server port.
        debug (bool): Enable Dash debug mode.
    """
    app = create_dash_app(llrf_app)
    logger.info(f"Starting Dash web interface on http://{host}:{port}")
    app.run(host=host, port=port, debug=debug, **kwargs)


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="LLRF Dash Live Waveform Monitor"
    )
    parser.add_argument(
        '--addr', default='192.168.19.37:803',
        help='LEEP device address (e.g. 192.168.19.37:803)'
    )
    parser.add_argument(
        '--conf', default='USPAS',
        help='Facility configuration (e.g. USPAS, ALSU, LEMP, AWA)'
    )
    parser.add_argument(
        '--host', default='0.0.0.0',
        help='Dash server host IP'
    )
    parser.add_argument(
        '--port', type=int, default=8050,
        help='Dash server port'
    )
    parser.add_argument(
        '--debug', action='store_true',
        help='Enable Dash debug mode'
    )
    parser.add_argument(
        '--bypass-bist', action='store_true',
        help='Disable BIST check'
    )
    args = parser.parse_args()

    llrf = LLRFApp(addr=args.addr, conf=args.conf, assert_system_bist=(not args.bypass_bist))
    run_dash(llrf, host=args.host, port=args.port, debug=args.debug)


if __name__ == '__main__':
    main()
