using Observables
using Base.Test

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

@testset "throttle" begin
    obs = Observable(1)
    throttled = throttle(10, obs)
    @test throttled[] == 1
    obs[] = 2
    sleep(0.1)
    @test throttled[] == 2
    obs[] = 3
    sleep(5)
    @test throttled[] == 2
    sleep(10)
    @test throttled[] == 3
end
