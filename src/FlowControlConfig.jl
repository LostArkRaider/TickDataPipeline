# src/FlowControlConfig.jl - Fixed Delay Configuration System
# Session 1 REDESIGNED: Replace timestamp-based delay with fixed delay configuration
# Simple millisecond delays (0-10,000ms) from config file
# FIXED: Added missing enum value exports

module FlowControlConfig

using ..GATypes
using ..VolumeExpansion  # FIXED: Import VolumeExpansion module for proper volume expansion
using TOML
using Dates

# FIXED: Export enum values individually so they can be accessed as ComplexBiquadGA.FIXED_DELAY
export FlowControlMode, FlowGateConfig, load_flow_control_config, save_flow_control_config,
       apply_fixed_delay, create_default_flow_config, validate_flow_config,
       NO_DELAY, FIXED_DELAY, apply_fixed_delay_validated, stream_expanded_ticks

# =============================================================================
# FLOW CONTROL CONFIGURATION TYPES (GPU-COMPATIBLE)
# =============================================================================

"""
Flow control mode enumeration
"""
@enum FlowControlMode begin
    NO_DELAY = 0        # Process at maximum speed
    FIXED_DELAY = 1     # Apply fixed millisecond delay
end

"""
Flow control configuration with fixed delays
GPU-COMPATIBLE: All Int32 for timing variables
"""
struct FlowGateConfig
    delay_mode::FlowControlMode         # NO_DELAY or FIXED_DELAY
    fixed_delay_ms::Int32              # 0 to 10,000 milliseconds (GPU-compatible)
    max_throughput_hz::Int32           # Optional throughput limiting (GPU-compatible)
    enable_timing_validation::Bool      # Validate actual vs target timing
    timing_tolerance_ms::Int32         # Acceptable timing deviation (GPU-compatible)
    
    # Constructor with validation
    function FlowGateConfig(delay_mode::FlowControlMode, 
                           fixed_delay_ms::Int32,
                           max_throughput_hz::Int32 = Int32(0),
                           enable_timing_validation::Bool = true,
                           timing_tolerance_ms::Int32 = Int32(10))
        # Validate delay range
        if fixed_delay_ms < Int32(0) || fixed_delay_ms > Int32(10000)
            error("Fixed delay must be between 0 and 10,000 milliseconds")
        end
        
        # Validate throughput
        if max_throughput_hz < Int32(0)
            error("Max throughput must be non-negative")
        end
        
        # Validate tolerance
        if timing_tolerance_ms < Int32(1)
            error("Timing tolerance must be at least 1ms")
        end
        
        new(delay_mode, fixed_delay_ms, max_throughput_hz, 
            enable_timing_validation, timing_tolerance_ms)
    end
end

# =============================================================================
# SIMPLE DELAY APPLICATION
# =============================================================================

"""
Apply fixed delay in milliseconds
Simple sleep-based implementation for flow gating
GPU-COMPATIBLE: Int32 parameter
"""
function apply_fixed_delay(delay_ms::Int32)
    if delay_ms <= Int32(0)
        return  # No delay
    end
    
    # Convert to seconds and sleep
    delay_seconds = Float32(delay_ms) / Float32(1000)  # R18: Float32() constructor
    sleep(delay_seconds)
end

"""
Apply delay with timing validation
Returns actual delay achieved in milliseconds
GPU-COMPATIBLE: Int32 parameters and return
"""
function apply_fixed_delay_validated(delay_ms::Int32, tolerance_ms::Int32)::Int32
    if delay_ms <= Int32(0)
        return Int32(0)
    end
    
    start_time = time_ns()
    apply_fixed_delay(delay_ms)
    end_time = time_ns()
    
    # Calculate actual delay achieved (truncate for conservative measurement)
    actual_delay_ns = end_time - start_time
    actual_delay_ms = Int32(trunc(Int64, actual_delay_ns / 1_000_000))  # Convert ns to ms (GPU-compatible)
    
    # Validate timing if requested
    timing_error_ms = abs(actual_delay_ms - delay_ms)
    if timing_error_ms > tolerance_ms
        @warn "Timing deviation: target $(delay_ms)ms, actual $(actual_delay_ms)ms (error: $(timing_error_ms)ms)"
    end
    
    return actual_delay_ms
end

# =============================================================================
# CONFIGURATION PERSISTENCE
# =============================================================================

"""
Create default flow control configuration
"""
function create_default_flow_config()::FlowGateConfig
    return FlowGateConfig(
        FIXED_DELAY,                    # Default to fixed delay mode
        Int32(0),                       # 0ms delay for maximum performance testing
        Int32(0),                       # No throughput limit
        true,                           # Enable timing validation
        Int32(10)                       # 10ms tolerance
    )
end

"""
Load flow control configuration from TOML file
"""
function load_flow_control_config(config_path::String)::FlowGateConfig
    if !isfile(config_path)
        @warn "Flow control config not found: $config_path, creating default"
        config = create_default_flow_config()
        save_flow_control_config(config, config_path)
        return config
    end
    
    try
        data = TOML.parsefile(config_path)
        
        # Parse delay mode
        mode_str = get(data, "delay_mode", "FIXED_DELAY")
        delay_mode = if mode_str == "NO_DELAY"
            NO_DELAY
        elseif mode_str == "FIXED_DELAY"
            FIXED_DELAY
        else
            @warn "Unknown delay mode: $mode_str, using FIXED_DELAY"
            FIXED_DELAY
        end
        
        return FlowGateConfig(
            delay_mode,
            Int32(get(data, "fixed_delay_ms", 100)),                    # GPU-compatible
            Int32(get(data, "max_throughput_hz", 0)),                   # GPU-compatible
            Bool(get(data, "enable_timing_validation", true)),
            Int32(get(data, "timing_tolerance_ms", 10))                 # GPU-compatible
        )
        
    catch e
        @error "Failed to load flow control config: $e"
        return create_default_flow_config()
    end
end

"""
Save flow control configuration to TOML file
"""
function save_flow_control_config(config::FlowGateConfig, config_path::String)
    # Ensure directory exists
    config_dir = dirname(config_path)
    if !isempty(config_dir) && !isdir(config_dir)
        mkpath(config_dir)
    end
    
    # Convert to TOML-compatible dict
    data = Dict{String, Any}(
        "delay_mode" => string(config.delay_mode),
        "fixed_delay_ms" => config.fixed_delay_ms,
        "max_throughput_hz" => config.max_throughput_hz,
        "enable_timing_validation" => config.enable_timing_validation,
        "timing_tolerance_ms" => config.timing_tolerance_ms,
        "created_at" => string(now()),
        "version" => "1.0"
    )
    
    # Write to file
    open(config_path, "w") do io
        TOML.print(io, data)
    end
    
    println("Saved flow control config: $config_path")
end

"""
Validate flow control configuration
"""
function validate_flow_config(config::FlowGateConfig)::Bool
    errors = String[]
    
    # Validate delay range
    if config.fixed_delay_ms < Int32(0) || config.fixed_delay_ms > Int32(10000)
        push!(errors, "Fixed delay $(config.fixed_delay_ms)ms outside valid range (0-10,000ms)")
    end
    
    # Validate throughput limit
    if config.max_throughput_hz < Int32(0)
        push!(errors, "Max throughput cannot be negative")
    end
    
    # Validate timing tolerance
    if config.timing_tolerance_ms < Int32(1) || config.timing_tolerance_ms > Int32(1000)
        push!(errors, "Timing tolerance $(config.timing_tolerance_ms)ms outside reasonable range (1-1000ms)")
    end
    
    # Check for conflicting settings
    if config.delay_mode == NO_DELAY && config.fixed_delay_ms > Int32(0)
        push!(errors, "NO_DELAY mode with non-zero fixed delay is conflicting")
    end
    
    if !isempty(errors)
        println("Flow control config validation errors:")
        for error in errors
            println("  - $error")
        end
        return false
    end
    
    println("Flow control config validation passed")
    return true
end

# =============================================================================
# STREAMING INTERFACE FOR SIMPLE STRING PROCESSING
# =============================================================================

"""
Process tick file with volume expansion and flow control
Returns channel of YM-format strings ready for TickHotLoopF32
GPU-COMPATIBLE: Int32 for counters
"""
function stream_expanded_ticks(file_path::String, flow_config::FlowGateConfig)::Channel{String}
    return Channel{String}() do channel
        if !isfile(file_path)
            @warn "Tick file not found: $file_path"
            return
        end
        
        original_lines = Int32(0)        # GPU-compatible
        expanded_lines = Int32(0)        # GPU-compatible
        last_emit_time = time_ns()
        
        open(file_path, "r") do file
            for line in eachline(file)
                original_lines += Int32(1)
                
                # Expand volume for this line
                expanded_strings = VolumeExpansion.process_tick_line_simple(line)
                
                # Apply flow control to each expanded string
                for expanded_string in expanded_strings
                    # Apply fixed delay if configured
                    if flow_config.delay_mode == FIXED_DELAY
                        current_time = time_ns()
                        elapsed_ms = Int32(trunc(Int64, (current_time - last_emit_time) / 1_000_000))  # GPU-compatible
                        
                        if elapsed_ms < flow_config.fixed_delay_ms
                            remaining_delay = flow_config.fixed_delay_ms - elapsed_ms
                            apply_fixed_delay(remaining_delay)
                        end
                        
                        last_emit_time = time_ns()
                    end
                    
                    # Send expanded string to TickHotLoopF32
                    put!(channel, expanded_string)
                    expanded_lines += Int32(1)
                end
                
                # Progress reporting
                if original_lines % Int32(10000) == Int32(0)
                    expansion_ratio = Float32(expanded_lines) / Float32(original_lines)  # R18: Float32() constructor
                    println("Processed $original_lines lines → $expanded_lines expanded ($(round(expansion_ratio, digits=2))x)")
                end
            end
        end
        
        expansion_ratio = Float32(expanded_lines) / Float32(max(original_lines, Int32(1)))  # R18: Float32() constructor
        println("Volume expansion complete: $original_lines → $expanded_lines lines ($(round(expansion_ratio, digits=2))x expansion)")
    end
end

end # module FlowControlConfig