using Test
using TickDataPipeline

@testset "TickDataPipeline.jl" begin
    include("test_broadcast_message.jl")
    include("test_volume_expansion.jl")
    include("test_tickhotloopf32.jl")
    include("test_triple_split.jl")
    include("test_integration.jl")
    include("test_pipeline_manager.jl")
end
