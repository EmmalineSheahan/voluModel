# Setup ----
library(terra)
library(tidyterra)
library(ggplot2)
library(voluModel) # Because of course
library(ggplot2) # For fancy plotting
library(viridisLite) # For high-contrast plotting palettes
library(dplyr) # To filter data
library(terra) # Now being transitioned in
library(sf) # Now being transitioned in
library(sp)
library(latticeExtra)
library(ggnewscale)

# Load data
oxygenSmooth <- rast(system.file("extdata/oxygenSmooth.tif",
                                 package='voluModel'))

occs <- read.csv(system.file("extdata/Steindachneria_argentea.csv",
                             package='voluModel'))

td <- tempdir()
unzip(system.file("extdata/woa18_decav_t00mn01_cropped.zip",
                  package = "voluModel"),
      exdir = paste0(td, "/temperature"), junkpaths = T)
temperature <- sf::st_read(paste0(td, "/temperature/woa18_decav_t00mn01_cropped.shp"))
temperature <- as(temperature, "Spatial")
temperature@data[temperature@data == -999.999] <- NA

# Turn into SpatRaster
template <- rast(nrows = length(unique(temperature@coords[,2])),
                 ncols = length(unique(temperature@coords[,1])),
                 extent = ext(temperature))
tempTerVal <- rasterize(x = temperature@coords, y = template,
                        values = temperature@data)

# Get names of depths
envtNames <- gsub("[d,M]", "", names(temperature))
envtNames[[1]] <- "0"
names(tempTerVal) <- envtNames
temperature <- tempTerVal

# Oxygen processing
names(oxygenSmooth) <- names(temperature)

occurrences <- occs %>% dplyr::select(decimalLongitude, decimalLatitude, depth) %>%
  distinct() %>% filter(dplyr::between(depth, 1, 2000))

# Gets the layer index for each occurrence by matching to depth
layerNames <- as.numeric(names(temperature))
occurrences$index <- unlist(lapply(occurrences$depth,
                                   FUN = function(x) which.min(abs(layerNames - x))))
indices <- unique(occurrences$index)
downsampledOccs <- data.frame()
for(i in indices){
  tempPoints <- occurrences[occurrences$index==i,]
  tempPoints <- downsample(tempPoints, temperature[[1]], verbose = FALSE)
  tempPoints$depth <- rep(layerNames[[i]], times = nrow(tempPoints))
  downsampledOccs <- rbind(downsampledOccs, tempPoints)
}
occsWdata <- downsampledOccs[,c("decimalLatitude", "decimalLongitude", "depth")]

occsWdata$temperature <- xyzSample(occs = occsWdata, temperature)
occsWdata$AOU <- xyzSample(occs = occsWdata, oxygenSmooth)
occsWdata <- occsWdata[complete.cases(occsWdata),]

# Land shapefile
land <- rnaturalearth::ne_countries(scale = "small", returnclass = "sf")[1]

# Study region
studyRegion <- marineBackground(occsWdata, buff = 1000000)

# Get limits
tempLims <- quantile(occsWdata$temperature,c(0, 1))
aouLims <- quantile(occsWdata$AOU,c(0, 1))

# Reclassify environmental bricks to presence/absence
temperaturePresence <- classify(temperature,
                                rcl = matrix(c(-Inf,tempLims[[1]],0,
                                               tempLims[[1]], tempLims[[2]], 1,
                                               tempLims[[2]], Inf, 0),
                                             ncol = 3, byrow = TRUE))
AOUpresence <- classify(oxygenSmooth,
                        rcl = matrix(c(-Inf, aouLims[[1]],0,
                                       aouLims[[1]], aouLims[[2]], 1,
                                       aouLims[[2]], Inf, 0),
                                     ncol = 3, byrow = TRUE))

# Put it all together
envelopeModel3D <- temperaturePresence * AOUpresence
envelopeModel3D <- mask(crop(envelopeModel3D, studyRegion),
                        mask = studyRegion)
names(envelopeModel3D) <- names(temperature)
rm(AOUpresence, downsampledOccs, occurrences, temperaturePresence,
   tempPoints, aouLims, envtNames, i, indices, layerNames, td, tempLims)

layerNames <- as.numeric(names(envelopeModel3D))
occsWdata$index <- unlist(lapply(occsWdata$depth, FUN = function(x) which.min(abs(layerNames - x))))
indices <- unique(occsWdata$index)

# Internal function shit ----
rast <- envelopeModel3D[[min(indices):max(indices)]]
title <- "Envelope Model of Luminous Hake,\n 20 to 700m"
landCol = "black"

redVal <- 1
blueVal <- 0
stepSize <- 1/(nlyr(rast) + 1)

plot.new()
plot(rast[[1]],
   col = c(rgb(0,0,0,0),
           rgb(redVal,0,blueVal,stepSize)),
   legend = FALSE, mar = c(2,2,3,2))

for(i in 2:nlyr(rast)){
  redVal <- redVal - stepSize
  blueVal <- blueVal + stepSize
  plot(rast[[i]], col = c(rgb(0,0,0,0),
                          rgb(redVal,0,blueVal,stepSize)),
       legend = FALSE, add = TRUE)
}

grat <- graticule(lon = seq(-180, 180, 10), lat = seq(-90,90,10), crs = crs(rast))
plot(grat, col="gray50", add = TRUE)

plot(land, col = landCol, add = TRUE)
title(main = title, cex.main = 1.1)
finalPlot <- recordPlot()
