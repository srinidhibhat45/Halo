using Halo.Core.Catalog;
using Halo.Core.Editing;
using Halo.Core.Motion;

namespace Halo.Core.Tests;

public class SpringTests
{
    private static (double Max, double Final, double TimeToRest) Run(SpringSpec spec, double from, double to, double dt = 1.0 / 60)
    {
        var spring = new Spring(from, spec) { Target = to };
        var max = from;
        for (var t = 0.0; t < 5; t += dt)
        {
            spring.Step(dt);
            max = Math.Max(max, spring.Value);
            if (spring.IsAtRest) return (max, spring.Value, t + dt);
        }
        return (max, spring.Value, double.PositiveInfinity);
    }

    [Fact(DisplayName = "A critically damped spring settles without overshoot")]
    public void Critical()
    {
        var (max, final, rest) = Run(RingMotion.Dismiss, 0, 1);
        Assert.Equal(1, final);
        Assert.True(max <= 1 + 1e-9, $"overshot to {max}");
        Assert.True(rest < 0.6, $"took {rest}s");
    }

    [Fact(DisplayName = "The appear spring overshoots slightly and settles")]
    public void Underdamped()
    {
        var (max, final, rest) = Run(RingMotion.Appear, 0, 1);
        Assert.Equal(1, final);
        Assert.InRange(max, 1.0, 1.03);
        Assert.True(rest < 1.0);
    }

    [Fact(DisplayName = "An over-damped spring creeps to its target")]
    public void Overdamped()
    {
        var (max, final, _) = Run(new SpringSpec(0.3, 1.6), 0, 1);
        Assert.Equal(1, final);
        Assert.True(max <= 1);
    }

    [Fact(DisplayName = "Stepping is exact: one big step equals many small ones")]
    public void FrameRateIndependent()
    {
        var a = new Spring(0, RingMotion.FanOut) { Target = 1 };
        var b = a;
        a.Step(0.1);
        for (var i = 0; i < 10; i++) b.Step(0.01);
        Assert.Equal(a.Value, b.Value, 9);
        Assert.Equal(a.Velocity, b.Velocity, 9);
    }

    [Fact(DisplayName = "Retargeting keeps the velocity, so motion reverses smoothly")]
    public void Retarget()
    {
        var spring = new Spring(0, RingMotion.Appear) { Target = 1 };
        spring.Step(0.05);
        var velocity = spring.Velocity;
        Assert.True(velocity > 0);
        spring.Target = 0;
        Assert.Equal(velocity, spring.Velocity);
        spring.Step(1.0 / 120);
        Assert.True(spring.Velocity < velocity);
    }

    [Fact(DisplayName = "Snap jumps and rests; speed scales the response")]
    public void SnapAndSpeed()
    {
        var spring = new Spring(0, RingMotion.Dim) { Target = 1 };
        spring.Snap(0.5);
        Assert.True(spring.IsAtRest);
        Assert.Equal(0.5, spring.Value);
        Assert.Equal(0.1, RingMotion.Dismiss.AtSpeed(2).Response, 9);
        Assert.Equal(RingMotion.Dismiss, RingMotion.Dismiss.AtSpeed(0));
    }

    [Fact(DisplayName = "The bloom opens hub first, then slots clockwise ~30 ms apart, in about 0.45 s for eight")]
    public void Bloom()
    {
        Assert.Equal(RingMotion.BloomLead, RingMotion.BloomDelay(0, 1), 9);
        Assert.Equal(0.03, RingMotion.BloomDelay(3, 1) - RingMotion.BloomDelay(2, 1), 9);
        Assert.InRange(RingMotion.BloomDuration(8, 1), 0.4, 0.5);
        Assert.Equal(RingMotion.BloomDuration(8, 1) / 2, RingMotion.BloomDuration(8, 2), 9);
        Assert.Equal(0, RingMotion.BloomDuration(8, 0));

        // Each slot is (at least) 95 % of the way out BloomSettle seconds after it starts.
        var slot = new Spring(0, RingMotion.SlotBloom) { Target = 1 };
        var peak = 0.0;
        for (var t = 0.0; t < RingMotion.BloomSettle; t += 0.001)
        {
            slot.Step(0.001);
            peak = Math.Max(peak, slot.Value);
        }
        Assert.True(slot.Value >= 0.95, $"only {slot.Value:F3} out");
        Assert.InRange(peak, 1.0, 1.06);   // a quick settle with a hint of overshoot
    }

    [Fact(DisplayName = "Timings scale with speed; zero speed means instant")]
    public void Timings()
    {
        Assert.Equal(0.1, RingMotion.DismissDuration(2), 9);
        Assert.Equal(0, RingMotion.DismissDuration(0));
        Assert.Equal(0, RingMotion.FlashDuration(1, animationsEnabled: false));
        Assert.Equal(0.16, RingMotion.FlashDuration(0.25, animationsEnabled: true), 9);
        Assert.Equal(0, RingMotion.Shake(0.31, 1));
        Assert.Equal(0, RingMotion.FanDelay(1, 3));
        Assert.Equal(RingMotion.FanStagger, RingMotion.FanDelay(0, 3), 9);
        Assert.Equal(0, RingMotion.Delayed(0.04, 0.05));
        Assert.Equal(1, RingMotion.Delayed(1, 0.05), 9);
    }
}

public class ConfigEditingTests
{
    [Fact(DisplayName = "Edits address nested rings of the global ring and app rings")]
    public void NestedEdits()
    {
        var config = HaloConfig.Default;
        var windows = new RingAddress(RingTarget.Everywhere).Child(5);
        Assert.Equal(6, config.RingAt(windows)?.SlotCount);

        var edited = config.SettingSlot(windows, 0, new Slot(new MediaAction(MediaCommand.Mute)));
        Assert.Equal(new MediaAction(MediaCommand.Mute), edited.RingAt(windows)![0].Action);
        Assert.Equal(new WindowAction(WindowCommand.Maximize), config.RingAt(windows)![0].Action);   // original untouched

        var profile = config.NewProfile("code.exe", "Code", copyGlobal: true);
        config = config.AddingProfile(profile);
        var app = new RingAddress(new RingTarget.App(profile.Id));
        Assert.Equal(8, config.RingAt(app)?.FilledCount);
        Assert.Empty(config.GlobalRing.Slots.Select(s => s.Id).Intersect(config.RingAt(app)!.Slots.Select(s => s.Id)));
        config = config.UpdatingRing(app, r => r.Resized(4));
        Assert.Equal(4, config.RingAt(app)?.SlotCount);
        Assert.Equal(["Code", "AI"], config.Breadcrumb(app.Child(3)));
        config = config.RemovingProfile(profile.Id);
        Assert.Null(config.RingAt(app));
    }

    [Fact(DisplayName = "Assigning an action keeps the slot's id and tint, resets its title and icon")]
    public void Assign()
    {
        var address = new RingAddress(RingTarget.Everywhere);
        var config = HaloConfig.Default.SettingSlot(address, 1,
            new Slot(Guid.Empty, new MediaAction(MediaCommand.Mute), "Old", new EmojiIcon("🙂"), RingColor.FromPreset(RingColorPreset.Red)));
        var assigned = config.AssigningAction(address, 1, new EditAction(EditCommand.Copy));
        var slot = assigned.GlobalRing[1];
        Assert.Equal(Guid.Empty, slot.Id);
        Assert.Null(slot.Title);
        Assert.Null(slot.Icon);
        Assert.Equal(RingColor.FromPreset(RingColorPreset.Red), slot.Tint);
    }

    [Fact(DisplayName = "Invalid addresses leave the config unchanged")]
    public void InvalidAddress()
    {
        var config = HaloConfig.Default;
        Assert.Same(config, config.UpdatingRing(new RingAddress(RingTarget.Everywhere).Child(0), r => r.Resized(4)));
        Assert.Same(config, config.UpdatingRing(new RingAddress(new RingTarget.App(Guid.NewGuid())), r => r.Resized(4)));
        Assert.Same(config, config.UpdatingProfile(Guid.NewGuid(), p => p with { IsEnabled = false }));
    }

    [Fact(DisplayName = "Addresses compare by value and walk up and down")]
    public void Addresses()
    {
        var root = new RingAddress(RingTarget.Everywhere);
        Assert.Equal(root.Child(3), new RingAddress(new RingTarget.Global(), [3]));
        Assert.Equal(root, root.Child(3).Parent);
        Assert.Null(root.Parent);
    }
}
