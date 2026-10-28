namespace Halo.Core.Motion;

/// <summary>
/// The shape of a spring, parameterised like SwiftUI's <c>spring(response:dampingFraction:)</c>:
/// <paramref name="Response"/> is the period of the undamped oscillation in seconds, and
/// <paramref name="DampingFraction"/> is 1 for critical damping (fastest settle without overshoot),
/// below 1 for a little overshoot, above 1 for a slower creep.
/// </summary>
public readonly record struct SpringSpec(double Response, double DampingFraction)
{
    /// <summary>The same spring played <paramref name="speed"/> times faster.</summary>
    public SpringSpec AtSpeed(double speed) => speed > 0 ? this with { Response = Response / speed } : this;
}

/// <summary>
/// A value pulled toward <see cref="Target"/> by a damped spring (unit mass). Stepping uses the
/// closed-form solution of the damped oscillator, so it is exact and stable for any frame time;
/// retargeting mid-flight keeps the velocity, so every motion can be interrupted and reversed
/// smoothly.
/// </summary>
public struct Spring
{
    /// <summary>Below these, a spring counts as at rest and snaps to its target.</summary>
    public const double RestDistance = 0.0005, RestSpeed = 0.005;

    public Spring(double value, SpringSpec spec)
    {
        Value = value;
        Target = value;
        Velocity = 0;
        Spec = spec;
    }

    public double Value { get; private set; }
    public double Velocity { get; private set; }
    public double Target { get; set; }
    public SpringSpec Spec { get; set; }

    public readonly bool IsAtRest => Value == Target && Velocity == 0;

    /// <summary>Jumps to <paramref name="value"/> and stops.</summary>
    public void Snap(double value)
    {
        Value = value;
        Target = value;
        Velocity = 0;
    }

    /// <summary>Advances the spring by <paramref name="dt"/> seconds.</summary>
    public void Step(double dt)
    {
        if (IsAtRest || dt <= 0) return;
        var response = Math.Max(Spec.Response, 1e-3);
        var omega = 2 * Math.PI / response;
        var zeta = Math.Max(Spec.DampingFraction, 0);
        var x0 = Value - Target;
        var v0 = Velocity;
        double x, v;

        if (Math.Abs(zeta - 1) < 1e-6)
        {
            // Critically damped: x = e^(-ωt) (x0 + (v0 + ω x0) t)
            var b = v0 + omega * x0;
            var decay = Math.Exp(-omega * dt);
            x = decay * (x0 + b * dt);
            v = decay * (v0 - omega * b * dt);
        }
        else if (zeta < 1)
        {
            // Under-damped: decaying oscillation at ωd.
            var a = zeta * omega;
            var wd = omega * Math.Sqrt(1 - zeta * zeta);
            var c = x0;
            var d = (v0 + a * x0) / wd;
            var decay = Math.Exp(-a * dt);
            var (sin, cos) = Math.SinCos(wd * dt);
            x = decay * (c * cos + d * sin);
            v = decay * ((-a * c + d * wd) * cos + (-a * d - c * wd) * sin);
        }
        else
        {
            // Over-damped: sum of two decaying exponentials.
            var root = Math.Sqrt(zeta * zeta - 1);
            var r1 = -omega * (zeta - root);
            var r2 = -omega * (zeta + root);
            var c2 = (v0 - r1 * x0) / (r2 - r1);
            var c1 = x0 - c2;
            var e1 = Math.Exp(r1 * dt);
            var e2 = Math.Exp(r2 * dt);
            x = c1 * e1 + c2 * e2;
            v = c1 * r1 * e1 + c2 * r2 * e2;
        }

        if (Math.Abs(x) < RestDistance && Math.Abs(v) < RestSpeed)
        {
            Value = Target;
            Velocity = 0;
        }
        else
        {
            Value = Target + x;
            Velocity = v;
        }
    }
}
