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

signal_ran = false

@testset "signals" begin
    using Observables.Signals

    # Signal with 0 arguments
    s0 = Signal{0}()

    # Function to call
    function slot0()
        global signal_ran
        signal_ran = true
    end

    # Connect and then call
    Signals.connect!(s0,slot0)
    emit(s0)

    # Test that the global variable changed
    @test signal_ran

    s2 = Signal{2}()

    function slot2(x,y)
        @test x == 1
        @test y == "test"
    end

    Signals.connect!(s2,slot2)
    emit(s2,1,"test")
end