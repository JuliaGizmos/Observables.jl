using Observables
using Test

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

    off(r, f)
    @test !(f in r.listeners)
    @test_throws KeyError off(r, f)
    r[] = 3 # shouldn't call test
end

@testset "onany" begin
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
    @test r2[] == 0
    r1[] = 1
    @test r2[] == 2

    r1 = Observable(2)
    r2 = map(+, r1, 1)
    @test r2[] == 3
    r1[] = 3
    @test r2[] == 4
end

@testset "macros" begin
    a = Observable(2)
    b = Observable(3)
    c = Observables.@map &a + &b
    @test c isa Observable
    @test c[] == 5
    a[] = 100
    sleep(0.1)
    @test c[] == 103

    a = Observable(2)
    b = Observable(3)
    c = Observable(10)
    Observables.@map! c &a + &b
    sleep(0.1)
    @test c[] == 10
    a[] = 100
    sleep(0.1)
    @test c[] == 103

    a = Observable(2)
    b = Observable(3)
    c = Observable(10)
    Observables.@on c[] = &a + &b
    sleep(0.1)
    @test c[] == 10
    a[] = 100
    sleep(0.1)
    @test c[] == 103
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
    @test v.second[] ≈ ℯ
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
