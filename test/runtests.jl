using Observables
using Test

@testset "ambiguities" begin
    if VERSION < v"1.2"  # Julia 1.0 is bad at detecting ambiguities
    elseif VERSION < v"1.6"
        @test isempty(detect_ambiguities(Base, Observables))
    else
        @test isempty(detect_ambiguities(Observables))
    end
end

@testset "construct and show" begin
    obs = Observable(5)
    @test string(obs) == "Observable{$Int} with 0 listeners. Value:\n5"
    on(identity, obs)
    @test string(obs) == "Observable{$Int} with 1 listeners. Value:\n5"
    on(x->nothing, obs)
    @test string(obs) == "Observable{$Int} with 2 listeners. Value:\n5"
    obs[] = 7
    @test string(obs) == "Observable{$Int} with 2 listeners. Value:\n7"
    obs = Observable{Any}()
    @test string(obs) == "Observable{Any} with 0 listeners. Value:\nnot assigned yet!"
end

@testset "listeners" begin
    r = Observable(0)
    @test r[] == 0
    r[] = 1
    @test r[] == 1

    f = on(r) do x
        r[] == 2
        @test x == 2
    end
    r[] = 2

    @test off(r, f)
    @test !(f in r.listeners)
    @test off(r, f) == false
    r[] = 3 # shouldn't call test
end

@testset "onany and map" begin
    r = Observable(0)
    tested = Ref(false)
    onany(1, r) do x, y
        @test x == 1
        @test y == 2
        tested[] = true
    end
    r[] = 2
    @test tested[]

    r1 = Observable(0)
    r2 = Observable(0)
    map!(x->x+1, r2, r1)
    @test r2[] == 1
    r2 = Observable(0)
    map!(x->x+1, r2, r1; update=false)
    @test r2[] == 0
    r1[] = 1
    @test r2[] == 2

    r1 = Observable(2)
    r2 = @inferred(map(+, r1, 1))
    @test r2[] === 3
    @test eltype(r2) === Int
    r1[] = 3
    @test r2[] == 4

    r3 = @inferred(map!(+, Observable{Float32}(), r1, 1))
    @test r3[] === 4.0f0
    @test eltype(r3) === Float32
    r1[] = 4
    @test r3[] === 5.0f0

    # Make sure `precompile` doesn't error
    precompile(r1)
end

@testset "disconnect observerfuncs" begin

    x = Observable(1)
    y = Observable(2)
    z = Observable(3)

    of1 = on(x) do x
        println(x)
    end

    of2_3 = onany(y, z) do y, z
        println(y, z)
    end

    off(of1)
    off.(of2_3)
    for obs in (x, y, z)
        @test isempty(obs.listeners)
    end
end

# this struct is just supposed to show that a value in memory was released
mutable struct ToFinalize
    val

    function ToFinalize(val, finalized_flag::Ref)
        tf = new(val)
        finalizer(tf) do tf
            finalized_flag[] = true
        end
    end
end

@testset "weak connections" begin
    a = Observable(1)

    finalized_flag = Ref(false)

    function create_a_dangling_listener()
        t = ToFinalize(1, finalized_flag)

        obsfunc = on(a; weak = true) do a
            t.val += 1
        end

        a[] = 2
        @test t.val == 2

        # obsfunc falls out of scope here and should deregister the closure
        # when it gets garbage collected, which should in turn free t
        nothing
    end

    GC.enable(false)
    create_a_dangling_listener()
    @test length(Observables.listeners(a)) == 1
    @test finalized_flag[] == false

    GC.enable(true)
    GC.gc()
    # somehow this needs a double sweep, maybe first obsfunc, then ToFinalize?
    GC.gc()
    @test isempty(Observables.listeners(a))
    @test finalized_flag[] == true
end

@testset "world age" begin
    # issue #50
    obs = Observable(0)
    t = @task for n=1:10
        obs[] = n
        sleep(0.1)
    end
    schedule(t)
    sleep(0.1)
    map(x->2x, obs)
    sleep(0.2)
    @test t.state !== :failed # !istaskfailed(t) is only available on Julia 1.3+
end

@testset "macros" begin
    a = Observable(2)
    b = Observable(3)
    c = Observables.@map &a + &b
    @test c isa Observable
    @test c[] == 5
    a[] = 100
    @test c[] == 103

    a = Observable(2)
    b = Observable(3)
    c = Observable(10)
    Observables.@map! c &a + &b
    @test c[] == 5
    a[] = 100
    @test c[] == 103

    a = Observable(2)
    b = Observable(3)
    c = Observable(10)
    Observables.@on c[] = &a + &b
    @test c[] == 10
    a[] = 100
    @test c[] == 103
end

@testset "observe_changes" begin
    o = Observable(0)
    changes = observe_changes(o)
    changes_approx = observe_changes(o, (x,y) -> abs(x-y) < 2)
    @test eltype(changes) == eltype(changes_approx) == Int
    @test changes[] == changes_approx[] == 0

    values = Int[]
    values_approx = Int[]
    on(changes) do v
        push!(values, v)
    end
    on(changes_approx) do v
        push!(values_approx, v)
    end

    for i in 1:100
        o[] = floor(Int, i/10)
    end
    @test values == 1:10
    @test values_approx == 2:2:10
end

@testset "async_latest" begin
    o = Observable(0)
    cnt = Ref(0)
    function compute_something(x)
        for i=1:10^7; rand() end
        cnt[] = cnt[] + 1
    end
    o_latest = async_latest(o, 1)

    on(compute_something, o_latest) # compute something on the latest update
    for i=1:5
        o[] = i
    end
    sleep(1)

    @test o_latest[] == 5
    @test cnt[] == 1

    for i=5:-1:1
        @async o[] = i
    end
    sleep(1)

    @test o_latest[] == 1
    @test cnt[] == 2 # only one more

    o = Observable(0)
    cnt[] = 0
    function compute_something(x)
        for i=1:10^8; rand() end
        cnt[] = cnt[] + 1
    end
    sleep(1)
    o_latest = async_latest(o, 3)

    on(compute_something, o_latest) # compute something on the latest update
    for i=1:5
        o[] = i
    end
    sleep(.1)

    @test o_latest[] == 5
    @test cnt[] == 3
end

@testset "connect!" begin
    a, b = Observable(""), Observable("")
    connect!(a, b)
    b[] = "Hi!"
    @test a[] == "Hi!"
end

@testset "throttle" begin
    obs = Observable(1)
    throttled = throttle(2, obs)
    @test throttled[] == 1
    obs[] = 2
    sleep(0.1)
    @test throttled[] == 2
    obs[] = 3
    sleep(1)
    @test throttled[] == 2
    sleep(2)
    @test throttled[] == 3
end

struct A<:Observables.AbstractObservable{Int}; end

struct B{T}<:Observables.AbstractObservable{T}
    output::Observable{T}
end

Observables.observe(b::B) = b.output

@testset "interface" begin
    a = A()
    @test_throws ErrorException a[]
    @test_throws ErrorException a[] = 2
    @test_throws ErrorException Observables.obsid(a)
    @test_throws ErrorException Observables.listeners(a)
    @test eltype(a) == Int

    b = B(Observable("test"))
    @test b[] == "test"
    b[] = "test2"
    sleep(0.1)
    @test b[] == "test2"
    @test isempty(Observables.listeners(b))
    @test eltype(b) == String
end

@testset "pair" begin
    v = Observables.ObservablePair(Observable(1.0), f = exp, g = log)
    @test length(v) == 2
    @test firstindex(v) == 1
    @test lastindex(v) == 2
    firstobs, lastobs = v
    @test firstobs[] == 1.0
    @test lastobs[] ≈ ℯ
    @test v.second[] ≈ ℯ
    @test first(v)[] ≈ 1.0
    @test last(v)[] ≈ ℯ
    @test v[2][] ≈ ℯ

    v.first[] = 0
    @test v.second[] ≈ 1
    v.second[] = 2
    @test v.first[] ≈ log(2)

    obs = Observable(Observable(2))
    o2 = Observables.flatten(obs)

    o2[] = 12
    sleep(0.1)
    @test obs[][] == 12
    obs[][] = 22
    sleep(0.1)
    @test o2[] == 22
    obs[] = Observable(11)
    sleep(0.1)
    @test o2[] == 11

    obs = Observable(Observable(Observable(10)))
    o2 = Observables.flatten(obs)
    @test o2[] == 10

    obs[] = Observable(Observable(13))
    @test o2[] == 13
end

@testset "async" begin
    y = Observable(@async begin
        sleep(0.5)
        return 1 + 1
    end)
    @test !isdefined(y, :val)
    while !isdefined(y, :val)
        sleep(0.001)
    end
    @test y[] == 2

    x = Observable(1)
    y = map(x) do val
        @async begin
            sleep(0.5)
            return val + 1
        end
    end
    @test !isdefined(y, :val)
    while !isdefined(y, :val)
        sleep(0.001)
    end
    @test y[] == 2

    x = Observable(1)
    y = map(x) do val
        Channel() do channel
            for i in 1:10
                put!(channel, i + val)
            end
        end
    end
    @test !isdefined(y, :val)
    vals = Int[]
    on(y) do val
        push!(vals, val)
    end
    while length(vals) != 10
        sleep(0.001)
    end
    @test vals == 2:11
    y = Observable(Channel() do channel
        for i in 1:10
            put!(channel, i + 1)
        end
    end)
    @test !isdefined(y, :val)
    vals = Int[]
    on(y) do val
        push!(vals, val)
    end
    while length(vals) != 10
        sleep(0.001)
    end
    @test vals == 2:11
end

@testset "copy" begin
    obs = Observable{Any}(:hey)
    obs_copy = copy(obs)
    obs[] = 1
    @test obs_copy[] == 1
end

@testset "methodlist" begin
    _only(list) = (@assert length(list) == 1; return list[1])  # `only` is avail in Julia 1.4+
    obs = Observable(1)
    obsf = on(obs) do x
        x + 1
    end
    line1 = -2 + @__LINE__
    obs2 = map(obs) do x
        x + 1
    end
    line2 = -2 + @__LINE__
    obsflist = onany(obs, 5) do x, y
        x + y
    end
    line3 = -2 + @__LINE__
    obsf2 = _only(obsflist)
    m = _only(Observables.methodlist(obsf).ms)
    @test occursin("runtests.jl:$line1", string(m))
    m = _only(Observables.methodlist(obsf.f).ms)
    @test occursin("runtests.jl:$line1", string(m))
    m = _only(Observables.methodlist(obs.listeners[2]).ms)
    @test occursin("runtests.jl:$line2", string(m))
    m = _only(Observables.methodlist(obsf2).ms)
    @test occursin("runtests.jl:$line3", string(m))
    obsf3 = on(sqrt, obs)
    @test Observables.methodlist(obsf3).mt.name === :sqrt
end

@testset "deprecations" begin
    a = Observable(1)
    b = @test_deprecated map(sqrt, a; init=13.0)
    @test b[] == 13.0
    a[] = 4
    @test b[] == 2.0
end
