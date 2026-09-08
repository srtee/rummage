# Example analysis for the rummage-app image.
#
# Run with:
#   apptainer run --bind "$(pwd)":/work rummage-app.sif example/analysis.R
# (from the repo root), or from inside example/:
#   cd example && apptainer run --bind "$(pwd)":/work ../rummage-app.sif analysis.R

library(ggplot2)
library(terra)

# Simple ggplot2 check.
p <- ggplot(mtcars, aes(x = wt, y = mpg)) +
    geom_point() +
    geom_smooth(method = "lm")
ggsave("mtcars-plot.png", p)
cat("wrote mtcars-plot.png\n")

# Simple terra check: raster math on an in-memory raster.
r <- rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10, ymin = 0, ymax = 10)
values(r) <- 1:100
cat("raster mean:", as.character(global(r, "mean", na.rm = TRUE)$mean), "\n")
cat("terra OK:", as.character(packageVersion("terra")), "\n")