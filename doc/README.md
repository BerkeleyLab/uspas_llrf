# USPAS LLRF firmware

[[_TOC_]]

## Clocking

As shown in the following diagram of the digitizer (Zest) board support,
the clock distribution chip (LMK01801) receives an external reference clock,
and the outputs of two divider groups drives ADC (AD9563) and DAC (AD9781) respectively,
where the DAC sampling clock is double of the ADC sampling clock, which is the same as the DSP clock.

![zest_clk](./fig/zest_clk.drawio.svg)

$$
    f_\text{dac\_clk} = 2 f_\text{adc\_clk} = 2 f_\text{dsp\_clk}
$$

## IQ representation conventions

There are two conventions for IQ decomposition of a RF signal $y$ at carrier frequency $\omega$:

1. Positive carrier frequency:

   As described in [Wikipedia](https://en.wikipedia.org/wiki/In-phase_and_quadrature_components#Narrowband_signal_model),

   $$
   \begin{align*}
       y(t) &= (I + jQ) \cdot e^{j\omega t} \\
       \Re(y(t)) &= I\cos(\omega t) - Q\sin(\omega t)
   \end{align*}
   $$

   This convention is used in this repository.

2. Negative carrier frequency:

   $$
   \begin{align*}
       y(t) &= (I + jQ) \cdot e^{j-\omega t} \\
       \Re(y(t)) &= I\cos(\omega t) + Q\sin(\omega t)
   \end{align*}
   $$

   This convention is used in `bedrock/dsp` RTL modules.

## Digital Down-Conversion (DDC)

For high precision digitization, [Non-IQ direct digital down-conversion](https://accelconf.web.cern.ch/l06/papers/thp004.pdf) is used to avoid aliasing.

With the normalized ADC IF frequency $\omega_d = 2\pi\frac{f_\text{IF\_ADC}}{f_\text{S}}$, the DDC NCO provides LO data streams of $\cos(n\omega_d)$ and $\sin(n\omega_d)$. Two measured successive samples are:

$$
\begin{pmatrix}
    y_{n-1} \\
    y
\end{pmatrix}
= \begin{pmatrix}
    \cos((n-1)\omega_d) & -\sin((n-1)\omega_d) \\
    \cos(n\omega_d)     & -\sin(n\omega_d)
\end{pmatrix}
\begin{pmatrix}
    I \\
    Q
\end{pmatrix}
$$

Solve $I$ and $Q$ using inverse matrix:

$$
\begin{pmatrix}
    I \\
    Q
\end{pmatrix}
= \frac{1}{\sin\omega_d}
\begin{pmatrix}
    \sin(n\omega_d)    & -\sin((n-1)\omega_d) \\
    \cos(n\omega_d)    & -\cos((n-1)\omega_d)
\end{pmatrix}
\begin{pmatrix}
    y_{n-1} \\
    y
\end{pmatrix}
$$

RTL implementation is in [`noniq_ddc.v`](llrf_dsp/noniq_ddc.v), where a serialized stream of IQ data is generated.
An interpolation module `fiq_interp.v` is used to convert to parallel I and Q sample streams. A DC-blocking module `fwashout.v` is inserted before the `noniq_ddc.v`. The full DDC is packaged in [`ddc.v`](llrf_dsp/ddc.v).

## Digital Up-Conversion (DUC)

A generic digital up-conversion scheme is implemented, in the `dac_clk` domain.

With the normalized DAC IF frequency $\omega = 2\pi\frac{f_\text{IF\_DAC}}{f_\text{S}}$ and phase offset $\theta$, given a complex base band signal $I + jQ_n$, the up-converted signal $y$ is:

$$
\begin{align*}
    y &= (I + jQ_n) \cdot e^{jn\omega} \\
    &= I\cos(\omega n + \theta) - Q\sin(\omega n + \theta) + j\left( Q\cos(\omega n + \theta) + I\sin(\omega n + \theta) \right) \\
    \Re(y) &= I\cos(\omega n + \theta) - Q\sin(\omega n + \theta) \\
    \Im(y) &= Q\cos(\omega n + \theta) + I\sin(\omega n + \theta)
\end{align*}
$$

Equation in matrix form:

$$
\begin{pmatrix}
    I_y \\
    Q_y
\end{pmatrix}
=\begin{pmatrix}
    I & -Q \\
    Q & I
\end{pmatrix}
\begin{pmatrix}
    \cos(\omega n + \theta) \\
    \sin(\omega n + \theta)
\end{pmatrix}
$$

To avoid aliasing, condition $\omega \in (-\pi, \pi)$ is due to the [Nyquist–Shannon sampling theorem](https://en.wikipedia.org/wiki/Nyquist%E2%80%93Shannon_sampling_theorem).


When operating in the [under-sampling](https://en.wikipedia.org/wiki/Undersampling) scheme, the signal location at the first Nyquist zone must be calculated to derive the effective NCO frequency value.

### Second Nyquist zone DUC

For example, the up conversion from base band to the 2nd Nyquist zone (i.e. $\frac{f_\text{S}}{2} < f_\text{IF\_DAC} < f_\text{S}$) is illustrated at Figure 32 (b) in [NCO Setting Examples](https://docs.amd.com/r/en-US/pg269-rf-data-converter/NCO-Frequency-Conversion), where the NCO frequency is set to be $-(f_\text{S} - f_\text{IF\_DAC})$ or $-f_\text{IF\_DAC}$. This flip of sign is known as the spectral inversion due to frequency folding around the Nyquist frequency.

In practice, this spectral flip is implemented by simply flipping the sign of the $\sin(\omega n + \theta)$ for the LO to rotate in a counter clock wise direction.

This approach is consistent with the NCO Modulator in many RF-DACs such as the [AD9174 (Figure 79)](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9174.pdf), and the [AMD RFSoC](https://docs.amd.com/r/en-US/pg269-rf-data-converter/RF-DAC-Numerical-Controlled-Oscillator-and-Mixer), where a standalone NCO with configurable frequency and phase is instantiated, allowing 1st or 2nd Nyquist zone modulation. For 2nd Nyquist zone operation, most DACs has a Mix-Mode available to increase the amplitude response.

### Digital Up Conversion DSP implementation

![digital up conversion](./fig/digital_up_conversion.drawio.svg)

## LLRF DSP

![zest_clk](./fig/llrf_dsp.drawio.svg)
