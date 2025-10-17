# src/PipelineConfig.jl - Comprehensive Pipeline Configuration
# Design Specification v2.4 Implementation
# TOML-based configuration with validation

using Dates
using TOML

"""
SignalProcessingConfig - Signal processing parameters

All features ALWAYS ENABLED (no enable/disable flags per design spec).

# Fields
- `agc_alpha::Float32`: AGC smoothing factor (e.g., 0.0625 = 1/16)
- `agc_min_scale::Int32`: AGC minimum scale limit
- `agc_max_scale::Int32`: AGC maximum scale limit
- `winsorize_delta_threshold::Int32`: Raw delta clipping threshold (applied before normalization)
- `min_price::Int32`: Minimum valid price
- `max_price::Int32`: Maximum valid price
- `max_jump::Int32`: Maximum allowed price jump
- `encoder_type::String`: Encoder selection ("hexad16", "cpm", or "amc")
- `cpm_modulation_index::Float32`: CPM modulation index h (0.5 = MSK, only used when encoder_type = "cpm")
- `cpm_lut_size::Int32`: CPM LUT size (must be 1024, only used when encoder_type = "cpm")
- `amc_carrier_period::Float32`: AMC carrier period in ticks (default: 16.0, only used when encoder_type = "amc")
- `amc_lut_size::Int32`: AMC LUT size (must be 1024, shares CPM_LUT_1024, only used when encoder_type = "amc")
- `tick_derivative_imag_scale::Float32`: DERIVATIVE encoder tick-level imaginary component scaling (2.0-4.0 recommended, only used when encoder_type = "derivative")
"""
struct SignalProcessingConfig
    agc_alpha::Float32
    agc_min_scale::Int32
    agc_max_scale::Int32
    winsorize_delta_threshold::Int32
    min_price::Int32
    max_price::Int32
    max_jump::Int32
    encoder_type::String
    cpm_modulation_index::Float32
    cpm_lut_size::Int32
    amc_carrier_period::Float32
    amc_lut_size::Int32
    tick_derivative_imag_scale::Float32

    function SignalProcessingConfig(;
        agc_alpha::Float32 = Float32(0.125),
        agc_min_scale::Int32 = Int32(4),
        agc_max_scale::Int32 = Int32(50),
        winsorize_delta_threshold::Int32 = Int32(10),  # Clips top 0.5% of deltas (data-driven)
        min_price::Int32 = Int32(36600),
        max_price::Int32 = Int32(43300),
        max_jump::Int32 = Int32(50),
        encoder_type::String = "amc",  # Default to AMC encoder (harmonic elimination for filter banks)
        cpm_modulation_index::Float32 = Float32(0.5),  # h=0.5 (MSK characteristics)
        cpm_lut_size::Int32 = Int32(1024),  # 1024-entry LUT (only size currently supported)
        amc_carrier_period::Float32 = Float32(16.0),  # AMC carrier period (16 ticks, matches HEXAD16)
        amc_lut_size::Int32 = Int32(1024),  # AMC LUT size (shares CPM_LUT_1024)
        tick_derivative_imag_scale::Float32 = Float32(4.0)  # DERIVATIVE tick-level imaginary scaling (2.0-4.0 recommended)
    )
        new(agc_alpha, agc_min_scale, agc_max_scale, winsorize_delta_threshold,
            min_price, max_price, max_jump, encoder_type, cpm_modulation_index, cpm_lut_size,
            amc_carrier_period, amc_lut_size, tick_derivative_imag_scale)
    end
end

"""
BarProcessingConfig - Bar-level signal processing parameters

Bar processing aggregates ticks into bars and applies signal processing
(normalization, jump guard, winsorizing, derivative encoding) at bar level.

# Fields
- `enabled::Bool`: Enable/disable bar processing (default: false)
- `ticks_per_bar::Int32`: Number of ticks per bar (e.g., 21, 144, 610)
- `normalization_window_bars::Int32`: Recalculate normalization every N bars (e.g., 24)
- `winsorize_bar_threshold::Int32`: Clip bar deltas to ±threshold (e.g., 50)
- `max_bar_jump::Int32`: Maximum allowed bar-to-bar delta (e.g., 100)
- `bar_derivative_imag_scale::Float32`: Scaling for bar-level velocity component (e.g., 4.0)

# Normalization Window
The normalization window should be significantly larger than a single bar:
- For 21-tick bars: use ~120 bars (normalization_window_bars = 120)
- For 144-tick bars: use ~24 bars (normalization_window_bars = 24)
- For 233-tick bars: use ~20 bars (normalization_window_bars = 20)
- General rule: normalization_window_bars ≥ 20

The normalization is recalculated every N bars (where N = normalization_window_bars).

# Example
```julia
bar_processing = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(21),
    normalization_window_bars = Int32(120),
    winsorize_bar_threshold = Int32(50),
    max_bar_jump = Int32(100),
    bar_derivative_imag_scale = Float32(4.0)
)
```
"""
struct BarProcessingConfig
    enabled::Bool
    ticks_per_bar::Int32
    normalization_window_bars::Int32
    winsorize_bar_threshold::Int32
    max_bar_jump::Int32
    bar_derivative_imag_scale::Float32

    function BarProcessingConfig(;
        enabled::Bool = false,
        ticks_per_bar::Int32 = Int32(144),
        normalization_window_bars::Int32 = Int32(24),
        winsorize_bar_threshold::Int32 = Int32(50),
        max_bar_jump::Int32 = Int32(100),
        bar_derivative_imag_scale::Float32 = Float32(4.0)
    )
        new(enabled, ticks_per_bar, normalization_window_bars,
            winsorize_bar_threshold, max_bar_jump, bar_derivative_imag_scale)
    end
end

"""
FlowControlConfig - Flow control parameters

# Fields
- `delay_ms::Float64`: Delay between ticks in milliseconds
"""
struct FlowControlConfig
    delay_ms::Float64

    function FlowControlConfig(; delay_ms::Float64 = 0.0)
        new(delay_ms)
    end
end

"""
ChannelConfig - Broadcasting channel parameters

# Fields
- `priority_buffer_size::Int32`: Buffer size for priority consumer
- `standard_buffer_size::Int32`: Buffer size for standard consumers
"""
struct ChannelConfig
    priority_buffer_size::Int32
    standard_buffer_size::Int32

    function ChannelConfig(;
        priority_buffer_size::Int32 = Int32(4096),
        standard_buffer_size::Int32 = Int32(2048)
    )
        new(priority_buffer_size, standard_buffer_size)
    end
end

"""
PerformanceConfig - Performance targets and limits

# Fields
- `target_latency_us::Int32`: Target processing latency (microseconds)
- `max_latency_us::Int32`: Maximum acceptable latency (microseconds)
- `target_throughput_tps::Float32`: Target throughput (ticks per second)
"""
struct PerformanceConfig
    target_latency_us::Int32
    max_latency_us::Int32
    target_throughput_tps::Float32

    function PerformanceConfig(;
        target_latency_us::Int32 = Int32(500),
        max_latency_us::Int32 = Int32(1000),
        target_throughput_tps::Float32 = Float32(10000.0)
    )
        new(target_latency_us, max_latency_us, target_throughput_tps)
    end
end

"""
PipelineConfig - Complete pipeline configuration

Comprehensive configuration for all pipeline components.

# Fields
- `tick_file_path::String`: Path to tick data file
- `signal_processing::SignalProcessingConfig`: Signal processing parameters
- `bar_processing::BarProcessingConfig`: Bar processing parameters
- `flow_control::FlowControlConfig`: Flow control parameters
- `channels::ChannelConfig`: Channel configuration
- `performance::PerformanceConfig`: Performance targets
- `pipeline_name::String`: Pipeline identifier
- `description::String`: Pipeline description
- `version::String`: Configuration version
- `created::DateTime`: Configuration creation time
"""
struct PipelineConfig
    tick_file_path::String
    signal_processing::SignalProcessingConfig
    bar_processing::BarProcessingConfig
    flow_control::FlowControlConfig
    channels::ChannelConfig
    performance::PerformanceConfig
    pipeline_name::String
    description::String
    version::String
    created::DateTime

    function PipelineConfig(;
        tick_file_path::String = "data/raw/YM 06-25.Last.txt",
        signal_processing::SignalProcessingConfig = SignalProcessingConfig(),
        bar_processing::BarProcessingConfig = BarProcessingConfig(),
        flow_control::FlowControlConfig = FlowControlConfig(),
        channels::ChannelConfig = ChannelConfig(),
        performance::PerformanceConfig = PerformanceConfig(),
        pipeline_name::String = "default",
        description::String = "Default tick processing pipeline",
        version::String = "1.0",
        created::DateTime = now()
    )
        new(tick_file_path, signal_processing, bar_processing, flow_control, channels, performance,
            pipeline_name, description, version, created)
    end
end

"""
    create_default_config()::PipelineConfig

Create default pipeline configuration with standard YM futures parameters.

# Returns
- `PipelineConfig`: Configuration with default values
"""
function create_default_config()::PipelineConfig
    return PipelineConfig()
end

"""
    load_config_from_toml(toml_path::String)::PipelineConfig

Load pipeline configuration from TOML file.

# Arguments
- `toml_path::String`: Path to TOML configuration file

# Returns
- `PipelineConfig`: Loaded configuration

# Example TOML Format
```toml
pipeline_name = "production"
description = "Production tick processing pipeline"
version = "1.0"
tick_file_path = "data/raw/YM 06-25.Last.txt"

[signal_processing]
agc_alpha = 0.0625
agc_min_scale = 4
agc_max_scale = 50
winsorize_delta_threshold = 10
min_price = 39000
max_price = 44000
max_jump = 50

[flow_control]
delay_ms = 1.0

[channels]
priority_buffer_size = 4096
standard_buffer_size = 2048

[performance]
target_latency_us = 500
max_latency_us = 1000
target_throughput_tps = 10000.0
```
"""
function load_config_from_toml(toml_path::String)::PipelineConfig
    if !isfile(toml_path)
        @warn "Config file not found: $toml_path, using defaults"
        return create_default_config()
    end

    toml_data = TOML.parsefile(toml_path)

    # Parse signal processing section
    sp = get(toml_data, "signal_processing", Dict{String,Any}())
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(get(sp, "agc_alpha", 0.0625)),
        agc_min_scale = Int32(get(sp, "agc_min_scale", 4)),
        agc_max_scale = Int32(get(sp, "agc_max_scale", 50)),
        winsorize_delta_threshold = Int32(get(sp, "winsorize_delta_threshold", 10)),
        min_price = Int32(get(sp, "min_price", 39000)),
        max_price = Int32(get(sp, "max_price", 44000)),
        max_jump = Int32(get(sp, "max_jump", 50)),
        encoder_type = String(get(sp, "encoder_type", "cpm")),
        cpm_modulation_index = Float32(get(sp, "cpm_modulation_index", 0.5)),
        cpm_lut_size = Int32(get(sp, "cpm_lut_size", 1024)),
        amc_carrier_period = Float32(get(sp, "amc_carrier_period", 16.0)),
        amc_lut_size = Int32(get(sp, "amc_lut_size", 1024)),
        tick_derivative_imag_scale = Float32(get(sp, "tick_derivative_imag_scale", 4.0))
    )

    # Parse bar processing section (optional)
    bp = get(toml_data, "bar_processing", Dict{String,Any}())
    bar_processing = BarProcessingConfig(
        enabled = get(bp, "enabled", false),
        ticks_per_bar = Int32(get(bp, "ticks_per_bar", 144)),
        normalization_window_bars = Int32(get(bp, "normalization_window_bars", 24)),
        winsorize_bar_threshold = Int32(get(bp, "winsorize_bar_threshold", 50)),
        max_bar_jump = Int32(get(bp, "max_bar_jump", 100)),
        bar_derivative_imag_scale = Float32(get(bp, "bar_derivative_imag_scale", 4.0))
    )

    # Parse flow control section
    fc = get(toml_data, "flow_control", Dict{String,Any}())
    flow_control = FlowControlConfig(
        delay_ms = Float64(get(fc, "delay_ms", 0.0))
    )

    # Parse channels section
    ch = get(toml_data, "channels", Dict{String,Any}())
    channels = ChannelConfig(
        priority_buffer_size = Int32(get(ch, "priority_buffer_size", 4096)),
        standard_buffer_size = Int32(get(ch, "standard_buffer_size", 2048))
    )

    # Parse performance section
    perf = get(toml_data, "performance", Dict{String,Any}())
    performance = PerformanceConfig(
        target_latency_us = Int32(get(perf, "target_latency_us", 500)),
        max_latency_us = Int32(get(perf, "max_latency_us", 1000)),
        target_throughput_tps = Float32(get(perf, "target_throughput_tps", 10000.0))
    )

    # Parse top-level fields
    tick_file_path = get(toml_data, "tick_file_path", "data/raw/YM 06-25.Last.txt")
    pipeline_name = get(toml_data, "pipeline_name", "loaded")
    description = get(toml_data, "description", "Loaded from TOML")
    version = get(toml_data, "version", "1.0")

    return PipelineConfig(
        tick_file_path = tick_file_path,
        signal_processing = signal_processing,
        bar_processing = bar_processing,
        flow_control = flow_control,
        channels = channels,
        performance = performance,
        pipeline_name = pipeline_name,
        description = description,
        version = version,
        created = now()
    )
end

"""
    save_config_to_toml(config::PipelineConfig, toml_path::String)

Save pipeline configuration to TOML file.

# Arguments
- `config::PipelineConfig`: Configuration to save
- `toml_path::String`: Path for output TOML file
"""
function save_config_to_toml(config::PipelineConfig, toml_path::String)
    toml_dict = Dict{String,Any}(
        "pipeline_name" => config.pipeline_name,
        "description" => config.description,
        "version" => config.version,
        "tick_file_path" => config.tick_file_path,
        "signal_processing" => Dict{String,Any}(
            "agc_alpha" => config.signal_processing.agc_alpha,
            "agc_min_scale" => config.signal_processing.agc_min_scale,
            "agc_max_scale" => config.signal_processing.agc_max_scale,
            "winsorize_delta_threshold" => config.signal_processing.winsorize_delta_threshold,
            "min_price" => config.signal_processing.min_price,
            "max_price" => config.signal_processing.max_price,
            "max_jump" => config.signal_processing.max_jump,
            "encoder_type" => config.signal_processing.encoder_type,
            "cpm_modulation_index" => config.signal_processing.cpm_modulation_index,
            "cpm_lut_size" => config.signal_processing.cpm_lut_size,
            "amc_carrier_period" => config.signal_processing.amc_carrier_period,
            "amc_lut_size" => config.signal_processing.amc_lut_size,
            "tick_derivative_imag_scale" => config.signal_processing.tick_derivative_imag_scale
        ),
        "bar_processing" => Dict{String,Any}(
            "enabled" => config.bar_processing.enabled,
            "ticks_per_bar" => config.bar_processing.ticks_per_bar,
            "normalization_window_bars" => config.bar_processing.normalization_window_bars,
            "winsorize_bar_threshold" => config.bar_processing.winsorize_bar_threshold,
            "max_bar_jump" => config.bar_processing.max_bar_jump,
            "bar_derivative_imag_scale" => config.bar_processing.bar_derivative_imag_scale
        ),
        "flow_control" => Dict{String,Any}(
            "delay_ms" => config.flow_control.delay_ms
        ),
        "channels" => Dict{String,Any}(
            "priority_buffer_size" => config.channels.priority_buffer_size,
            "standard_buffer_size" => config.channels.standard_buffer_size
        ),
        "performance" => Dict{String,Any}(
            "target_latency_us" => config.performance.target_latency_us,
            "max_latency_us" => config.performance.max_latency_us,
            "target_throughput_tps" => config.performance.target_throughput_tps
        )
    )

    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end
end

"""
    validate_config(config::PipelineConfig)::Tuple{Bool, Vector{String}}

Validate pipeline configuration.

# Arguments
- `config::PipelineConfig`: Configuration to validate

# Returns
- `Tuple{Bool, Vector{String}}`: (is_valid, error_messages)
"""
function validate_config(config::PipelineConfig)::Tuple{Bool, Vector{String}}
    errors = String[]

    # Validate signal processing
    sp = config.signal_processing
    if sp.agc_min_scale >= sp.agc_max_scale
        push!(errors, "agc_min_scale must be < agc_max_scale")
    end
    if sp.agc_min_scale < Int32(1)
        push!(errors, "agc_min_scale must be >= 1")
    end
    if sp.agc_alpha <= Float32(0.0) || sp.agc_alpha >= Float32(1.0)
        push!(errors, "agc_alpha must be in range (0.0, 1.0)")
    end
    if sp.winsorize_delta_threshold <= Int32(0)
        push!(errors, "winsorize_delta_threshold must be positive")
    end
    if sp.min_price >= sp.max_price
        push!(errors, "min_price must be < max_price")
    end
    if sp.max_jump <= Int32(0)
        push!(errors, "max_jump must be positive")
    end

    # Validate encoder configuration
    if sp.encoder_type != "hexad16" && sp.encoder_type != "cpm" && sp.encoder_type != "amc" && sp.encoder_type != "derivative"
        push!(errors, "encoder_type must be either \"hexad16\", \"cpm\", \"amc\", or \"derivative\"")
    end
    if sp.encoder_type == "cpm"
        if sp.cpm_modulation_index <= Float32(0.0) || sp.cpm_modulation_index > Float32(1.0)
            push!(errors, "cpm_modulation_index must be in range (0.0, 1.0]")
        end
        if sp.cpm_lut_size != Int32(1024)
            push!(errors, "cpm_lut_size must be 1024 (only size currently supported)")
        end
    end
    if sp.encoder_type == "amc"
        if sp.amc_carrier_period <= Float32(0.0)
            push!(errors, "amc_carrier_period must be positive")
        end
        if sp.amc_lut_size != Int32(1024)
            push!(errors, "amc_lut_size must be 1024 (only size currently supported)")
        end
    end
    if sp.encoder_type == "derivative"
        if sp.tick_derivative_imag_scale <= Float32(0.0)
            push!(errors, "tick_derivative_imag_scale must be positive")
        end
    end

    # Validate flow control
    if config.flow_control.delay_ms < 0.0
        push!(errors, "delay_ms must be non-negative")
    end

    # Validate channels
    if config.channels.priority_buffer_size < Int32(1)
        push!(errors, "priority_buffer_size must be >= 1")
    end
    if config.channels.standard_buffer_size < Int32(1)
        push!(errors, "standard_buffer_size must be >= 1")
    end

    # Validate bar processing
    bp = config.bar_processing
    if bp.ticks_per_bar < Int32(1)
        push!(errors, "ticks_per_bar must be >= 1")
    end
    if bp.normalization_window_bars < Int32(1)
        push!(errors, "normalization_window_bars must be >= 1")
    end
    if bp.normalization_window_bars < Int32(20) && bp.enabled
        push!(errors, "normalization_window_bars should be >= 20 for stable normalization (recommended)")
    end
    if bp.winsorize_bar_threshold <= Int32(0)
        push!(errors, "winsorize_bar_threshold must be positive")
    end
    if bp.max_bar_jump <= Int32(0)
        push!(errors, "max_bar_jump must be positive")
    end
    if bp.bar_derivative_imag_scale <= Float32(0.0)
        push!(errors, "bar_derivative_imag_scale must be positive")
    end

    # Validate performance
    perf = config.performance
    if perf.max_latency_us <= perf.target_latency_us
        push!(errors, "max_latency_us must be > target_latency_us")
    end
    if perf.target_throughput_tps <= Float32(0.0)
        push!(errors, "target_throughput_tps must be positive")
    end

    return (isempty(errors), errors)
end
