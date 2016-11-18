#!/usr/bin/env julia

#Plot a histogram of the number of the trip distance ("Trip Distance").
histogram(df, :Trip_distance, bins=650, leg=false,
    xlims = (0, 650), title = "NYC Green Taxis, Sep. 2015",
    xlabel = "Distance (mi.)", ylabel = "Count")
png(joinpath(plotdir, "q2-histogram"))
info("Histogram saved to q2-histogram.png")

########################################

#Filter out trips with distance of exactly 0
tripdistf = filter(d->d>0, Array(df[:Trip_distance]))
nz = size(df, 1) - size(tripdistf, 1)
info("Removing $nz trips of distance 0")

#Filter out one crazy outlier
tripdistf = filter(d->d<250, tripdistf)

#Attempt to fit trip distances to log-normal distribution

xmin = 0
xmax = 30
nbins = 100
tripdistf = filter(x -> xmin ≤ x ≤ xmax, tripdistf)
histogram(tripdistf, bins=nbins, label = "Histogram", xlims=(xmin, xmax),
    xlabel = "Distance (mi.)", ylabel = "Count")

d = fit(LogNormal, tripdistf)
pdfplot!(d, scale=length(tripdistf), xlims=(xmin, xmax), bins=nbins, color=:blue, width=2, alpha=0.5,
    label = "log-normal (mu=$(round(d.μ, 3)), sigma=$(round(d.σ, 3)))",
)

c = fit(Gamma, tripdistf)
pdfplot!(d, scale=length(tripdistf), xlims=(xmin, xmax), bins=nbins, color=:red, width=2, alpha=0.5,
    label = "Gamma (k=$(round(c.α, 3)), theta=$(round(c.θ, 3)))")


png(joinpath(plotdir, "q2-histogram-fit"))
info("Histogram saved to q2-histogram-fit.png")
