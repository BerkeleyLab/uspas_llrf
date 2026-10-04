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
from uspas_llrf.model.llrf_shell import DacDriveSel, WaveTrigSel

logger = logging.getLogger(__name__)

# dac_drive_sel mux in llrf_shell.v: which loop's I/Q lands on DAC A / DAC B
DAC_DRIVE_OPTIONS = [
    {'label': ' I0Q0 (loop0 drives)', 'value': int(DacDriveSel.I0Q0)},
    {'label': ' I1Q1 (loop1 drives)', 'value': int(DacDriveSel.I1Q1)},
    {'label': ' I0I1 (dual loops, I)', 'value': int(DacDriveSel.I0I1)},
    {'label': ' Q0Q1 (dual loops, Q)', 'value': int(DacDriveSel.Q0Q1)},
]

# llrf_shell.v wave_trig_sel: trigger source of the cic_waves circle buffer.
# Except for Always, recording stops once the buffer is full and restarts
# on the next trigger.
# cbuf_post_delay powers up as 0, which disables the fault record freeze
# (cic_waves.v); the dash sets this instead so a permit drop is recorded.
CBUF_POST_DELAY_DEFAULT = 1

WAVE_TRIG_OPTIONS = [
    {'label': ' Always', 'value': int(WaveTrigSel.Always)},
    {'label': ' Internal', 'value': int(WaveTrigSel.Internal)},
    {'label': ' External', 'value': int(WaveTrigSel.External)},
    {'label': ' Software', 'value': int(WaveTrigSel.Software)},
    {'label': ' EVR', 'value': int(WaveTrigSel.EVR)},
    {'label': ' Mixed (ext | soft)', 'value': int(WaveTrigSel.Mixed)},
]
SOFT_TRIG_MODES = (int(WaveTrigSel.Software), int(WaveTrigSel.Mixed))


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


def format_slow_records(slow):
    """Flatten the status part of a decoded SlowData into Parameter / Value
    rows for a DataTable."""
    if slow is None:
        return []
    return [
        {'Parameter': 'Record type',
         'Value': 'FAULT (stopped by record_en)' if slow.fault else 'normal'},
        {'Parameter': 'cbuf_stat1', 'Value': f'{slow.cbuf_stat1:#06x}'},
        {'Parameter': 'Buffer wrap', 'Value': str(slow.buf_wrap)},
        {'Parameter': 'Last addr (stat2)', 'Value': f'{slow.last_addr:#06x}'},
        {'Parameter': 'cbuf_count', 'Value': str(slow.cbuf_count)},
        {'Parameter': 'tag / tag_old',
         'Value': f'{slow.tag:#04x} / {slow.tag_old:#04x}'
                  + (' (changed)' if slow.tag_changed else '')},
        {'Parameter': 'EVR timestamp',
         'Value': f'{slow.evr_seconds} s + {slow.evr_ticks} ticks'},
        {'Parameter': 'Cycle counter', 'Value': str(slow.cycles)},
    ]


def format_slow_adc_records(slow, signals):
    """ADC min/max rows of a decoded SlowData, one per ADC channel."""
    if slow is None:
        return []
    return [{'Channel': ch, 'adc_min': int(lo), 'adc_max': int(hi),
             'adc_pp': int(hi) - int(lo)}
            for ch, lo, hi in zip(signals, slow.adc_min, slow.adc_max)]


def format_inlk_records(df, permit_sum):
    """Rows of LLRFApp.get_inlk_status, one per channel, plus a summary
    row carrying rf_pwr_permit_sum in the rf_pwr_latch column it is
    derived from."""
    records = df.reset_index().rename(
        columns={'index': 'Channel'}).to_dict('records')
    for r in records:
        for col in ['Fault Amp [cnt]', 'Amp Lo [cnt]', 'Amp Hi [cnt]']:
            r[col] = f"{r[col]:.1f}"
    records.append({'Channel': 'rf_pwr_permit_sum',
                    'rf_pwr_latch': permit_sum})
    return records


def format_arc_records(df, permit_sum):
    """Rows of LLRFApp.get_arc_status, one per arc channel, plus a summary
    row carrying arc_permit_sum in the arc_permit_latch column it is
    derived from."""
    records = df.reset_index().rename(
        columns={'index': 'Channel'}).to_dict('records')
    records.append({'Channel': 'arc_permit_sum',
                    'arc_permit_latch': permit_sum})
    return records


def format_permit_records(regs, drive_names):
    """Rows of the RF permit chain from LLRFApp.get_permit_status, grouped
    as external, internal and final. Each group ends with its combined
    permit, derived here except drive_permit_out which is read back."""
    def row(group, permit, value, source):
        return {'Group': group, 'Permit': permit, 'Value': value & 1,
                'Source': source}
    ext = regs['ext_permit_bypass'] | (
        regs['drive_permit_in'] & regs['slow_permit_in'])
    internal = regs['rf_pwr_permit_sum'] & regs['arc_permit_sum'] & (
        regs['hpa_permit_out'])
    drive_out = regs['drive_permit_out']
    records = [
        row('External', 'drive_permit_in', regs['drive_permit_in'],
            'RF drive control'),
        row('External', 'slow_permit_in', regs['slow_permit_in'],
            'master interlock PLC'),
        row('External', 'ext_permit_bypass', regs['ext_permit_bypass'],
            '1 = external permits bypassed'),
        row('External', 'external_permit', ext,
            '= bypass | drive & slow'),
        row('Internal', 'rf_pwr_permit_sum', regs['rf_pwr_permit_sum'],
            'RF power interlock'),
        row('Internal', 'arc_permit_sum', regs['arc_permit_sum'],
            'arc interlock'),
        row('Internal', 'hpa_osc_permit', regs['hpa_permit_out'],
            'hpa_permit_out'),
        row('Internal', 'internal_permit', internal,
            '= rf_pwr & arc & hpa_osc'),
        row('Final', 'drive_permit_out', drive_out,
            'readback of external & internal'),
    ]
    for n, name in enumerate(drive_names):
        soft = (regs['soft_drive_enable'] >> n) & 1
        records.append(row('Final', f'soft_drive_enable[{n}]', soft,
                           f'{name} software enable'))
        records.append(row('Final', f'RF permit {name}', soft & drive_out,
                           f'= soft_drive_enable[{n}] & drive_permit_out'))
    return records


def create_dash_app(llrf_app: LLRFApp) -> dash.Dash:
    """Create and configure a Plotly Dash application for an LLRFApp instance.

    Args:
        llrf_app (LLRFApp): Connected LLRFApp hardware device interface.

    Returns:
        dash.Dash: Configured Dash application.
    """
    # LEEPDevice keeps the UDP destination as (host, port)
    dest = getattr(llrf_app, 'dest', None)
    dev_addr = f"{dest[0]}:{dest[1]}" if dest else "unknown"
    app = dash.Dash(__name__,
                    title=f"LLRF Live - {llrf_app.app_name} @ {dev_addr}")

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

    try:
        cbuf_post_delay_init = int(llrf_app.read_reg('cbuf_post_delay'))
        # A write while the permit is down lets the stopped post-delay
        # counter run and fires a late fault record, so only enable the
        # freeze while drive_permit_out is up.
        if cbuf_post_delay_init == 0:
            if int(llrf_app.read_reg('drive_permit_out')):
                llrf_app.write_reg('cbuf_post_delay', CBUF_POST_DELAY_DEFAULT)
                cbuf_post_delay_init = CBUF_POST_DELAY_DEFAULT
                logger.info("cbuf_post_delay was 0 (freeze disabled), "
                            f"set to {CBUF_POST_DELAY_DEFAULT}")
            else:
                logger.warning("cbuf_post_delay is 0 (freeze disabled) and "
                               "drive_permit_out is 0; clear the permit and "
                               "set cbuf_post_delay to record faults")
    except Exception as e:
        logger.warning(f"Could not read cbuf_post_delay, defaulting to 0: {e}")
        cbuf_post_delay_init = 0

    try:
        wave_trig_sel_init = int(llrf_app.read_reg('wave_trig_sel'))
    except Exception as e:
        logger.warning(f"Could not read wave_trig_sel, defaulting to Always: {e}")
        wave_trig_sel_init = int(WaveTrigSel.Always)

    try:
        wave_samp_per_init = int(llrf_app.wave_samp_per)
    except Exception as e:
        logger.warning(f"Could not read wave_samp_per, defaulting to 1: {e}")
        wave_samp_per_init = 1
    wave_samp_per_max = 127  # 7-bit register
    wave_samp_marks = {v: str(v) for v in (1, 16, 32, 64, 96, 127)}

    def fmt_time_ns(ns):
        for unit, scale in (('s', 1e9), ('ms', 1e6), ('µs', 1e3)):
            if ns >= scale:
                return f"{ns / scale:.3g} {unit}"
        return f"{ns:.3g} ns"

    def time_scale_text():
        # CIC sample period and circle buffer span per channel, the
        # oscilloscope time/div equivalent of wave_samp_per.
        ts_ns = llrf_app.cic_ts_ns
        n_samples = 2**16 // llrf_app.cic_n_chan // 2
        cic_mon = llrf_app.model.cic_mon
        return (f"wave_samp_per={cic_mon.wave_samp_per}, "
                f"cic_wave_shift={cic_mon.wave_shift}, "
                f"Ts={fmt_time_ns(ts_ns)}, "
                f"span={fmt_time_ns(ts_ns * n_samples)} "
                f"({n_samples} samples/chan)")

    table_header_style = {
        'backgroundColor': '#34495e',
        'color': 'white',
        'fontWeight': 'bold',
        'textAlign': 'center'
    }
    table_cell_style = {
        'textAlign': 'center',
        'padding': '6px 8px',
        'fontSize': '13px'
    }

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
                    html.Div([
                        html.H2(
                            "LLRF Live Monitor & Control: "
                            f"{llrf_app.app_name} @ {dev_addr}",
                            style={'color': '#2c3e50', 'margin': '0'}
                        ),
                        # code hash from the LEEP config ROM, as `leep gitid`
                        html.Div(
                            "git_rev_id: "
                            f"{getattr(llrf_app, 'codehash', None) or 'unknown'}",
                            id='git-rev-id',
                            style={'fontSize': '12px', 'color': '#7f8c8d',
                                   'fontFamily': 'monospace',
                                   'marginTop': '4px'}
                        )
                    ]),
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
                            "Trigger Mode (wave_trig_sel):",
                            style={'fontWeight': 'bold', 'display': 'block'}
                        ),
                        html.Div(
                            style={'display': 'flex', 'gap': '10px',
                                   'alignItems': 'center'},
                            children=[
                                dcc.RadioItems(
                                    id='wave-trig-sel',
                                    options=WAVE_TRIG_OPTIONS,
                                    value=wave_trig_sel_init,
                                    inline=True
                                ),
                                html.Button(
                                    'Soft Trigger',
                                    id='soft-trigger-btn',
                                    n_clicks=0,
                                    disabled=(wave_trig_sel_init
                                              not in SOFT_TRIG_MODES),
                                    style={'padding': '4px 10px',
                                           'cursor': 'pointer'}
                                )
                            ]
                        ),
                        html.Div(
                            id='wave-trig-status',
                            style={'fontSize': '11px', 'color': '#7f8c8d'}
                        )
                    ]),
                    html.Div(
                        style={'minWidth': '320px', 'flex': '1'},
                        children=[
                            html.Label(
                                "CIC Time Scale (wave_samp_per):",
                                style={'fontWeight': 'bold',
                                       'display': 'block'}),
                            dcc.Slider(
                                id='wave-samp-per',
                                min=1, max=wave_samp_per_max, step=1,
                                value=wave_samp_per_init,
                                marks=wave_samp_marks,
                                tooltip={'placement': 'bottom',
                                         'always_visible': True},
                                updatemode='mouseup'),
                            html.Div(
                                id='wave-samp-status',
                                style={'fontSize': '11px',
                                       'color': '#7f8c8d'})
                        ]
                    ),
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
                id='slow-panel',
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
                               'flexWrap': 'wrap', 'gap': '10px',
                               'marginBottom': '10px'},
                        children=[
                            html.H3(
                                "Slow Data & Waveform Status (read_slow_data)",
                                style={'color': '#2c3e50', 'margin': '0'}
                            ),
                            html.Div(
                                id='slow-fault-badge',
                                style={'fontWeight': 'bold',
                                       'padding': '4px 10px',
                                       'borderRadius': '4px'}
                            ),
                            html.Div(
                                style={'display': 'flex', 'gap': '15px',
                                       'alignItems': 'center'},
                                children=[
                                    html.Div([
                                        html.Label(
                                            "cbuf_post_delay [buffers]:",
                                            style={'fontSize': '11px',
                                                   'fontWeight': 'bold',
                                                   'display': 'block'}),
                                        dcc.Input(
                                            id='cbuf-post-delay',
                                            type='number', min=0,
                                            max=0xffff, step=1,
                                            value=cbuf_post_delay_init,
                                            debounce=True,
                                            style={'width': '80px'})
                                    ]),
                                    dcc.Checklist(
                                        id='hold-on-fault',
                                        options=[{
                                            'label': ' Stop auto refresh on fault',
                                            'value': 'on'}],
                                        value=['on'],
                                        style={'fontSize': '12px'}
                                    )
                                ]
                            )
                        ]
                    ),
                    html.Div(
                        id='slow-ctrl-status',
                        style={'fontSize': '11px', 'color': '#7f8c8d',
                               'marginBottom': '8px'}
                    ),
                    html.Div(
                        style={'display': 'flex', 'flexWrap': 'wrap',
                               'gap': '20px'},
                        children=[
                            html.Div(
                                style={'flex': '1', 'minWidth': '320px'},
                                children=[dash_table.DataTable(
                                    id='slow-status-table',
                                    columns=[
                                        {'name': 'Parameter', 'id': 'Parameter'},
                                        {'name': 'Value', 'id': 'Value'}
                                    ],
                                    data=[],
                                    style_header=table_header_style,
                                    style_cell={**table_cell_style,
                                                'textAlign': 'left'},
                                    style_cell_conditional=[
                                        {'if': {'column_id': 'Value'},
                                         'fontFamily': 'monospace'}
                                    ],
                                    style_data_conditional=[
                                        {'if': {'row_index': 'odd'},
                                         'backgroundColor': '#f8f9fa'},
                                        {'if': {'filter_query':
                                                '{Value} contains "FAULT"'},
                                         'backgroundColor': '#fdecea',
                                         'color': '#c0392b',
                                         'fontWeight': 'bold'}
                                    ]
                                )]
                            ),
                            html.Div(
                                style={'flex': '1', 'minWidth': '320px'},
                                children=[dash_table.DataTable(
                                    id='slow-adc-table',
                                    columns=[
                                        {'name': 'Channel', 'id': 'Channel'},
                                        {'name': 'ADC min', 'id': 'adc_min'},
                                        {'name': 'ADC max', 'id': 'adc_max'},
                                        {'name': 'Peak-peak', 'id': 'adc_pp'}
                                    ],
                                    data=[],
                                    style_header=table_header_style,
                                    style_cell=table_cell_style,
                                    style_data_conditional=[
                                        {'if': {'row_index': 'odd'},
                                         'backgroundColor': '#f8f9fa'}
                                    ]
                                )]
                            )
                        ]
                    ),
                    html.Div(
                        id='slow-last-fault',
                        style={'fontSize': '12px', 'color': '#c0392b',
                               'marginTop': '8px'}
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
                    html.H3(
                        "RF Power Interlock (get_inlk_status)",
                        style={'color': '#2c3e50', 'marginTop': '0',
                               'marginBottom': '4px'}
                    ),
                    html.Div(
                        "fault_amp is latched at the drop of the drive "
                        "permit. Amp Lo/Hi are the inlk_amp_lo/hi "
                        "thresholds; [cnt] columns are divided by the "
                        "interlock gain to ADC counts. Status bits: 1 = OK, 0 = tripped. "
                        "rf_pwr_permit_sum = AND over channels of "
                        "(rf_pwr_latch | ~inlk_permit_mask).",
                        style={'fontSize': '11px', 'color': '#7f8c8d',
                               'marginBottom': '8px'}
                    ),
                    dash_table.DataTable(
                        id='inlk-table',
                        columns=[
                            {'name': 'Channel', 'id': 'Channel'},
                            {'name': 'fault_amp', 'id': 'fault_amp'},
                            {'name': 'Fault Amp [cnt]',
                             'id': 'Fault Amp [cnt]'},
                            {'name': 'Amp Lo [cnt]', 'id': 'Amp Lo [cnt]'},
                            {'name': 'Amp Hi [cnt]', 'id': 'Amp Hi [cnt]'},
                            {'name': 'Raw Status', 'id': 'rf_pwr_status'},
                            {'name': 'First Fault',
                             'id': 'rf_pwr_first_fault_status'},
                            {'name': 'Latched Status', 'id': 'rf_pwr_latch'},
                            {'name': 'Interlocked',
                             'id': 'inlk_permit_mask'}
                        ],
                        data=[],
                        style_table={'overflowX': 'auto'},
                        style_header=table_header_style,
                        style_cell=table_cell_style,
                        style_data_conditional=[
                            {'if': {'row_index': 'odd'},
                             'backgroundColor': '#f8f9fa'},
                            # tripped channels that are in the permit mask
                            *[{'if': {'filter_query':
                                      f'{{{col}}} = 0 && '
                                      '{inlk_permit_mask} = 1',
                                      'column_id': col},
                               'backgroundColor': '#fdecea',
                               'color': '#c0392b',
                               'fontWeight': 'bold'}
                              for col in ['rf_pwr_status',
                                          'rf_pwr_first_fault_status',
                                          'rf_pwr_latch']],
                            {'if': {'filter_query':
                                    '{Channel} = "rf_pwr_permit_sum"'},
                             'fontWeight': 'bold',
                             'borderTop': '2px solid #34495e'},
                            {'if': {'filter_query':
                                    '{Channel} = "rf_pwr_permit_sum" && '
                                    '{rf_pwr_latch} = 0'},
                             'backgroundColor': '#fdecea',
                             'color': '#c0392b'}
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
                    html.H3(
                        "Arc Detector Interlock (get_arc_status)",
                        style={'color': '#2c3e50', 'marginTop': '0',
                               'marginBottom': '4px'}
                    ),
                    html.Div(
                        "Status bits: 1 = OK, 0 = tripped. "
                        "arc_permit_sum = AND over channels of "
                        "(arc_permit_latch | ~arc_permit_mask).",
                        style={'fontSize': '11px', 'color': '#7f8c8d',
                               'marginBottom': '8px'}
                    ),
                    dash_table.DataTable(
                        id='arc-table',
                        columns=[
                            {'name': 'Channel', 'id': 'Channel'},
                            {'name': 'Raw Status', 'id': 'arc_permit_raw'},
                            {'name': 'Latched Status',
                             'id': 'arc_permit_latch'},
                            {'name': 'Interlocked',
                             'id': 'arc_permit_mask'}
                        ],
                        data=[],
                        style_table={'overflowX': 'auto'},
                        style_header=table_header_style,
                        style_cell=table_cell_style,
                        style_data_conditional=[
                            {'if': {'row_index': 'odd'},
                             'backgroundColor': '#f8f9fa'},
                            # tripped channels that are in the permit mask
                            *[{'if': {'filter_query':
                                      f'{{{col}}} = 0 && '
                                      '{arc_permit_mask} = 1',
                                      'column_id': col},
                               'backgroundColor': '#fdecea',
                               'color': '#c0392b',
                               'fontWeight': 'bold'}
                              for col in ['arc_permit_raw',
                                          'arc_permit_latch']],
                            {'if': {'filter_query':
                                    '{Channel} = "arc_permit_sum"'},
                             'fontWeight': 'bold',
                             'borderTop': '2px solid #34495e'},
                            {'if': {'filter_query':
                                    '{Channel} = "arc_permit_sum" && '
                                    '{arc_permit_latch} = 0'},
                             'backgroundColor': '#fdecea',
                             'color': '#c0392b'}
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
                    html.H3(
                        "RF Permit (get_permit_status)",
                        style={'color': '#2c3e50', 'marginTop': '0',
                               'marginBottom': '4px'}
                    ),
                    html.Div(
                        "1 = permit, 0 = trip. drive_permit_out = "
                        "external_permit & internal_permit; each drive "
                        "is on with its soft_drive_enable bit and "
                        "drive_permit_out.",
                        style={'fontSize': '11px', 'color': '#7f8c8d',
                               'marginBottom': '8px'}
                    ),
                    dash_table.DataTable(
                        id='permit-table',
                        columns=[
                            {'name': 'Group', 'id': 'Group'},
                            {'name': 'Permit', 'id': 'Permit'},
                            {'name': 'Value', 'id': 'Value'},
                            {'name': 'Source', 'id': 'Source'}
                        ],
                        data=[],
                        style_table={'overflowX': 'auto'},
                        style_header=table_header_style,
                        style_cell=table_cell_style,
                        style_data_conditional=[
                            {'if': {'row_index': 'odd'},
                             'backgroundColor': '#f8f9fa'},
                            # combined permits close each group
                            {'if': {'filter_query':
                                    '{Permit} = "external_permit" || '
                                    '{Permit} = "internal_permit" || '
                                    '{Permit} = "drive_permit_out" || '
                                    '{Permit} contains "RF permit"'},
                             'fontWeight': 'bold'},
                            {'if': {'filter_query':
                                    '{Value} = 0 && '
                                    '{Permit} != "ext_permit_bypass"',
                                    'column_id': 'Value'},
                             'backgroundColor': '#fdecea',
                             'color': '#c0392b',
                             'fontWeight': 'bold'},
                            {'if': {'filter_query':
                                    '{Value} = 1 && '
                                    '{Permit} = "ext_permit_bypass"',
                                    'column_id': 'Value'},
                             'backgroundColor': '#fff4e5',
                             'color': '#d35400',
                             'fontWeight': 'bold'}
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
        Output('slow-ctrl-status', 'children'),
        Input('cbuf-post-delay', 'value'),
        prevent_initial_call=True
    )
    def set_cbuf_post_delay(value):
        # cic_waves.v: circle buffer stops writing value cbuf_sync's after
        # record_en (sum_drive_enable) drops; 0 disables the freeze.
        if value is None:
            return ""
        try:
            llrf_app.write_reg('cbuf_post_delay', int(value))
            note = " (freeze disabled)" if int(value) == 0 else ""
            return (f"cbuf_post_delay={int(value)}{note} at "
                    f"{time.strftime('%H:%M:%S')}")
        except Exception as e:
            return f"cbuf_post_delay write failed: {e}"

    @app.callback(
        Output('wave-trig-status', 'children'),
        Output('soft-trigger-btn', 'disabled'),
        Input('wave-trig-sel', 'value'),
        Input('soft-trigger-btn', 'n_clicks'),
        prevent_initial_call=True
    )
    def set_wave_trig_sel(value, _n_clicks):
        if value is None:
            return "", True
        soft_disabled = int(value) not in SOFT_TRIG_MODES
        try:
            if dash.ctx.triggered_id == 'soft-trigger-btn':
                llrf_app.write_reg('soft_trigger', 1)  # single-cycle
                return (f"soft_trigger at {time.strftime('%H:%M:%S')}",
                        soft_disabled)
            llrf_app.write_reg('wave_trig_sel', int(value))
            name = WaveTrigSel(int(value)).name
            return (f"wave_trig_sel={name} ({int(value)}) at "
                    f"{time.strftime('%H:%M:%S')}", soft_disabled)
        except Exception as e:
            return f"Trigger write failed: {e}", soft_disabled

    @app.callback(
        Output('wave-samp-status', 'children'),
        Input('wave-samp-per', 'value')
    )
    def set_wave_samp_per(value):
        # Fires on page load to show the current time scale.
        if value is None:
            return ""
        try:
            value = int(value)
            if value != llrf_app.model.cic_mon.wave_samp_per:
                # The setter rebuilds the model with the new CIC gain and
                # writes cic_wave_shift along with wave_samp_per to avoid
                # saturation; cic waveforms are rescaled by cic_wfm_gain.
                llrf_app.wave_samp_per = value
                # Flush the buffer recorded across the change; in triggered
                # modes none may come, the request then stays armed.
                try:
                    llrf_app.read_cbuf_data()
                except TimeoutError:
                    pass
            return f"{time_scale_text()} at {time.strftime('%H:%M:%S')}"
        except Exception as e:
            return f"wave_samp_per write failed: {e}"

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

    def read_inlk():
        """rf_pwr interlock table rows with a rf_pwr_permit_sum row."""
        try:
            df, permit_sum = llrf_app.get_inlk_status()
        except Exception as e:
            logger.error(f"Error reading interlock status: {e}")
            return []
        return format_inlk_records(df, permit_sum)

    def read_arc():
        """Arc interlock table rows with an arc_permit_sum row."""
        try:
            df, permit_sum = llrf_app.get_arc_status()
        except Exception as e:
            logger.error(f"Error reading arc interlock status: {e}")
            return []
        return format_arc_records(df, permit_sum)

    def read_permit():
        """RF permit chain table rows."""
        try:
            regs = llrf_app.get_permit_status()
        except Exception as e:
            logger.error(f"Error reading permit status: {e}")
            return []
        return format_permit_records(
            regs, llrf_app.signals[-llrf_app.n_dac:])

    def read_slow():
        """Slow data snapshot of the buffer transferred last.

        Returns (SlowData or None, error message)."""
        try:
            return llrf_app.read_slow_data(flip=False), ""
        except Exception as e:
            logger.error(f"Error reading slow data: {e}")
            return None, f"slow data read failed: {e}"

    def fault_badge(slow):
        if slow is None:
            return "slow data: n/a", {'backgroundColor': '#ecf0f1',
                                      'color': '#7f8c8d'}
        if slow.fault:
            return "FAULT RECORD", {'backgroundColor': '#e74c3c',
                                    'color': 'white'}
        return "normal record", {'backgroundColor': '#27ae60',
                                 'color': 'white'}

    @app.callback(
        Output('wfm-graph', 'figure'),
        Output('rfmon-table', 'data'),
        Output('inlk-table', 'data'),
        Output('arc-table', 'data'),
        Output('permit-table', 'data'),
        Output('status-text', 'children'),
        Output('slow-status-table', 'data'),
        Output('slow-adc-table', 'data'),
        Output('slow-fault-badge', 'children'),
        Output('slow-fault-badge', 'style'),
        Output('slow-last-fault', 'children'),
        Output('auto-refresh-check', 'value'),
        Input('live-interval', 'n_intervals'),
        Input('fetch-btn', 'n_clicks'),
        State('wfm-source-select', 'value'),
        State('plot-mode-select', 'value'),
        State('signal-select', 'value'),
        State('hold-on-fault', 'value'),
        State('slow-fault-badge', 'style'),
        State('wave-trig-sel', 'value')
    )
    def update_plot_and_rfmon(_n_intervals, _n_clicks, source, plot_mode,
                              selected_sigs, hold_on_fault, badge_style,
                              trig_sel):
        fig, rfmon_data, status = update_wfm(
            source, plot_mode, selected_sigs, trig_sel)

        # The slow block snapshots on the buffer transfer selected by
        # slow_snap_cic, so read it right after the waveform it belongs to.
        slow, slow_err = read_slow()
        badge, style = fault_badge(slow)
        style = {**(badge_style or {}), **style}
        last_fault = dash.no_update
        auto_refresh = dash.no_update
        if slow is not None and slow.fault:
            last_fault = (f"Last fault record at {time.strftime('%H:%M:%S')}: "
                          f"cbuf_count={slow.cbuf_count}, "
                          f"last_addr={slow.last_addr:#06x}, "
                          f"wrap={slow.buf_wrap}")
            if source == 'cic' and fig is not dash.no_update:
                fig.update_layout(title=f"{fig.layout.title.text} "
                                        "[FAULT RECORD]")
            if 'on' in (hold_on_fault or []):
                auto_refresh = []
                last_fault += " (auto refresh stopped)"
        if slow_err:
            status = f"{status} | {slow_err}"
        return (fig, rfmon_data, read_inlk(), read_arc(), read_permit(),
                status,
                format_slow_records(slow),
                format_slow_adc_records(slow, llrf_app.signals[:llrf_app.n_adc]),
                badge, style, last_fault, auto_refresh)

    def update_wfm(source, plot_mode, selected_sigs, trig_sel=None):
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
                # Triggered modes hand over a buffer only after a trigger:
                # poll briefly and keep the last waveform until one comes.
                triggered = (
                    trig_sel is not None
                    and int(trig_sel) != int(WaveTrigSel.Always)
                )
                df = llrf_app.get_cic_wfm_df(
                    timeout=0.1 if triggered else 1.0)
        except TimeoutError as e:
            if source == 'cic' and triggered:
                name = WaveTrigSel(int(trig_sel)).name
                return (dash.no_update, rfmon_data,
                        f"Waiting for {name} trigger at "
                        f"{time.strftime('%H:%M:%S')}, "
                        "showing last waveform")
            return go.Figure(layout={'title': f"Error: {e}"}), \
                rfmon_data, f"Error: {e}"
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
