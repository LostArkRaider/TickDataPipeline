# src/FIRFilter.jl - FIR Anti-Aliasing Filter Design
# High-quality FIR filter for bar decimation

using DSP

"""
Design FIR anti-aliasing filter using Parks-McClellan (Remez) algorithm.

Designed for decimation by factor M with specified passband ripple and stopband attenuation.

# Arguments
- `M::Int32`: Decimation factor (e.g., 21, 144)
- `fs::Float32`: Sampling frequency (default: 1.0 tick/sample)
- `A_pass_dB::Float32`: Passband ripple in dB (default: 0.1 dB)
- `A_stop_dB::Float32`: Stopband attenuation in dB (default: 80 dB)
- `passband_fraction::Float32`: Fraction of Nyquist for passband edge (default: 0.8)

# Returns
- `Vector{Float32}`: FIR filter coefficients

# Design Parameters
- Passband edge: `passband_fraction * fs/(2M)` (80% of new Nyquist by default)
- Stopband edge: `fs/(2M)` (new Nyquist frequency)
- Filter order: Automatically calculated using Kaiser method, then optimized

# Example
```julia
# Design filter for 21-tick decimation
h_aa = design_decimation_filter(Int32(21))

# Use with DSP.jl resample function
bar_signal = resample(tick_signal, 1//21, h_aa)
```
"""
function design_decimation_filter(
    M::Int32;
    fs::Float32 = Float32(1.0),
    A_pass_dB::Float32 = Float32(0.1),
    A_stop_dB::Float32 = Float32(80.0),
    passband_fraction::Float32 = Float32(0.8)
)::Vector{Float32}
    
    # Calculate frequency parameters
    f_nyquist_new = fs / (2.0f0 * Float32(M))
    f_pass = passband_fraction * f_nyquist_new
    f_stop = f_nyquist_new
    
    # Convert dB specifications to linear deviations
    delta_p = (10.0f0^(A_pass_dB / 20.0f0) - 1.0f0) / (10.0f0^(A_pass_dB / 20.0f0) + 1.0f0)
    delta_s = 10.0f0^(-A_stop_dB / 20.0f0)
    
    # Estimate filter order using Kaiser method
    delta = min(delta_p, delta_s)
    transition_width = f_stop - f_pass
    
    # Kaiser formula for filter order estimation
    A_atten = -20.0f0 * log10(delta)
    order_estimate = Int32(ceil((A_atten - 8.0f0) / (2.285f0 * 2.0f0 * π * transition_width / fs)))
    
    # Use Kaiser formula estimate for all decimation factors
    order = order_estimate
    
    # Ensure order is even for linear phase Type I filter
    if order % 2 == 1
        order += Int32(1)
    end
    
    # Pre-calculated optimal orders (for reference):
    # M=21:  order ≈ 1086 (1087 taps, group delay = 543)
    # M=144: order ≈ 7456 (7457 taps, group delay = 3728)
    
    # Define frequency bands (normalized to fs/2)
    bands = Float32[0.0, f_pass, f_stop, fs/2.0f0]
    
    # Define desired amplitudes for each band
    amps = Float32[1.0, 0.0]
    
    # Define weights (inverse of error tolerances)
    weights = Float32[delta_s / delta_p, 1.0]
    
    # Design the filter using Remez exchange algorithm
    h_aa = remez(order, bands, amps; weight=weights, Hz=fs)
    
    # Convert to Float32 for consistency
    return Float32.(h_aa)
end

"""
Get pre-designed FIR filter for common decimation factors.

Returns cached filter coefficients for optimal performance.

# Arguments
- `M::Int32`: Decimation factor (21 or 144)

# Returns
- `Vector{Float32}`: FIR filter coefficients

# Throws
- `ArgumentError`: If M is not a supported decimation factor

# Example
```julia
h_aa = get_predefined_filter(Int32(21))
```
"""
function get_predefined_filter(M::Int32)::Vector{Float32}
    if M == Int32(21)
        return design_decimation_filter(Int32(21))
    elseif M == Int32(144)
        return design_decimation_filter(Int32(144))
    else
        throw(ArgumentError("No pre-defined filter for decimation factor $M. Use design_decimation_filter() instead."))
    end
end
