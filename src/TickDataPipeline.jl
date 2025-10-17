module TickDataPipeline

# Updated: 2025-10-04 - QUAD-4 rotation fix
using Dates

# Core types (Session 1)
include("BroadcastMessage.jl")

# Exports from BroadcastMessage.jl
export BroadcastMessage
export create_broadcast_message, update_broadcast_message!
export FLAG_OK, FLAG_MALFORMED, FLAG_HOLDLAST, FLAG_CLIPPED, FLAG_AGC_LIMIT

# Volume expansion (Session 2)
include("VolumeExpansion.jl")

# Exports from VolumeExpansion.jl
export stream_expanded_ticks
export encode_timestamp_to_int64, decode_timestamp_from_int64
export parse_tick_line

# Signal processing (Session 3)
include("TickHotLoopF32.jl")

# Exports from TickHotLoopF32.jl
export TickHotLoopState, create_tickhotloop_state
export process_tick_signal!
export apply_quad4_rotation, phase_pos_global
export process_tick_cpm!  # CPM encoder function
export process_tick_amc!  # AMC encoder function (shares CPM_LUT_1024)
export CPM_LUT_1024  # CPM/AMC lookup table (shared by both encoders)

# Channel broadcasting (Session 4)
include("TripleSplitSystem.jl")

# Exports from TripleSplitSystem.jl
export ConsumerType, PRIORITY, MONITORING, ANALYTICS
export ConsumerChannel, TripleSplitManager
export create_triple_split_manager
export subscribe_consumer!, unsubscribe_consumer!
export broadcast_to_all!, deliver_to_consumer!
export get_consumer_stats, get_manager_stats

# Configuration and orchestration (Session 5)
include("PipelineConfig.jl")

# Bar processing (Session Bar Processor)
include("BarProcessor.jl")

include("PipelineOrchestrator.jl")

# Exports from PipelineConfig.jl
export PipelineConfig, create_default_config
export SignalProcessingConfig, BarProcessingConfig, FlowControlConfig, ChannelConfig, PerformanceConfig
export load_config_from_toml, save_config_to_toml, validate_config

# Exports from BarProcessor.jl
export BarProcessorState
export create_bar_processor_state, process_tick_for_bars!

# Exports from PipelineOrchestrator.jl
export PipelineManager, PipelineMetrics
export create_pipeline_manager
export run_pipeline, run_pipeline!
export stop_pipeline!
# Note: process_single_tick_through_pipeline! is internal only (not exported)

end # module TickDataPipeline
