# Load required libraries
library(ggplot2)
library(dplyr)
library(tidyr)
library(cowplot)  # Alternatively, you could use patchwork
library(scales)   # For formatting axis labels

# Read command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Check if the correct number of arguments is provided
if (length(args) < 4) {
  stop("Please provide the mode ('genome_plot' or 'region_plot'), followed by the required arguments: <Mode> <BAF file> <LRR file> <Region BED file (only for region_plot)> <Output Directory>")
}

# Assign command-line arguments to variables
mode <- args[1]
baf_file <- args[2]
lrr_file <- args[3]
output_dir <- args[length(args)]

# Ensure the output directory exists
if (!dir.exists(output_dir)) {
  dir.create(output_dir)
}

# Load the BAF and LRR data using the provided file paths
baf_data <- read.table(gzfile(baf_file), header = TRUE)
lrr_data <- read.table(gzfile(lrr_file), header = TRUE)

# Ensure columns are named correctly
colnames(baf_data) <- c("Chr", "Start", "End", "BAF")
colnames(lrr_data) <- c("Chr", "Start", "End", "LRR")

library(segmented)

getSmoothLine <- function(LRRs, region=NULL, smoothNum = 10) {
  rowNum <- nrow(LRRs)
  smoothed <- LRRs %>%
    arrange(Start) %>%
    mutate(smtGroup = as.integer(1:rowNum / smoothNum)) %>%
    group_by(smtGroup) %>%
    summarise(Pos = median(Start), LRR = median(LRR)) %>%
    ungroup()

  return(smoothed)
}

# Function to plot the entire genome
genome_plot <- function() {
  # Unique chromosomes
  chromosomes <- unique(lrr_data$Chr)

  # Create a list to hold plots
  lrr_plots <- list()
  baf_plots <- list()

  # Generate plots for each chromosome
  for (chr in chromosomes) {
    # Filter data for the current chromosome
    lrr_chr_data <- lrr_data %>% filter(Chr == chr)
    baf_chr_data <- baf_data %>% filter(Chr == chr)

    smooth_line <- getSmoothLine(lrr_chr_data)
    # Create LRR plot
    lrr_plot <- ggplot(lrr_chr_data) +
      geom_point(aes(x = Start, y = LRR), color = "#2a2a2a") +
      geom_line(data = smooth_line, aes(x = Pos, y = LRR), color = "#ff3333") +
      geom_rect(aes(xmin = min(Start), xmax = min(Start) + 100000, ymin = -Inf, ymax = Inf), 
                fill = "yellow", alpha = 0.005) +
      geom_rect(aes(xmin = max(Start) - 100000, xmax = max(Start), ymin = -Inf, ymax = Inf),
                fill = "yellow", alpha = 0.005) +
      theme_minimal() +
      labs(x = NULL, y = "LRR", title = paste("chr", chr, sep="")) +
      geom_hline(yintercept = 0, linetype = "dotted", color = "#555555") +
      coord_cartesian(ylim = c(-1, 1)) +
      scale_x_continuous(labels = label_number()) +
      scale_y_continuous(expand = c(0, 0))

    # Create BAF plot
    baf_plot <- ggplot(baf_chr_data) +
      geom_point(aes(x = Start, y = BAF), color = "#2a2a2a") +
      theme_minimal() +
      labs(x = "Position", y = "BAF") +
      geom_hline(yintercept = 0.5, linetype = "dotted", color = "#555555") +
      coord_cartesian(ylim = c(0, 1)) +
      scale_x_continuous(labels = label_number()) +
      scale_y_continuous(expand = c(0, 0))

    # Store plots in lists
    lrr_plots[[chr]] <- lrr_plot
    baf_plots[[chr]] <- baf_plot
  }

  # Combine plots for each chromosome
  all_plots <- lapply(chromosomes, function(chr) {
    plot_grid(lrr_plots[[chr]], baf_plots[[chr]], align = "v", ncol = 1)
  })
  # Split all plots into chunks of 12
  plot_chunks <- split(all_plots, ceiling(seq_along(all_plots) / 12))

  # Combine all chunks into a single plot
  combined_plot <- plot_grid(plotlist = unlist(plot_chunks, recursive = FALSE), ncol = 4)

  output_file <- file.path(output_dir, "plot_genome.png")
  ggsave(output_file, plot = combined_plot, width = 30, height = 40, dpi = 300)
}

region_plot <- function(region_file, min_padding=600000) {
  # Add tryCatch to handle potential errors when reading the region file
  regions <- tryCatch({
    regions_data <- read.table(region_file, header = FALSE)
    if (nrow(regions_data) == 0) {
      message("Region file is empty. No regions to plot.")
      return(invisible(NULL))  # Return silently without error
    }
    regions_data
  }, error = function(e) {
    message("Error reading region file: ", e$message)
    return(invisible(NULL))  # Return silently without error
  })
  
  # If regions is NULL, return without processing further
  if (is.null(regions)) {
    return(invisible(NULL))
  }

  colnames(regions) <- c("Chr", "Start", "End", "Type")

  # Iterate over each region and create plots
  for (i in 1:nrow(regions)) {
    region <- regions[i, ]
    padding = (region$End - region$Start)
    if (padding <= min_padding) {
      padding = min_padding
    }
    padded_start = region$Start - padding
    padded_end = region$End + padding

    # Filter BAF and LRR data for the current region
    filtered_baf <- baf_data %>% 
      filter(Chr == region$Chr & Start >= padded_start & Start <= padded_end)

    filtered_lrr <- lrr_data %>% 
      filter(Chr == region$Chr & Start >= padded_start & Start <= padded_end)

    smooth_line <- getSmoothLine(filtered_lrr, region)

    # Create the LRR plot with smooth line
    lrr_plot <- ggplot(filtered_lrr) +
      geom_point(aes(x = Start, y = LRR), color = "#2a2a2a", size= 0.3) +
      geom_line(data = smooth_line, aes(x = Pos, y = LRR), color = "#ff3333") +
      theme_minimal() +
      labs(x = NULL, y = "LRR", title = paste(region$Chr, ":", region$Start, "-", region$End, sep="")) +
      geom_hline(yintercept = 0, linetype = "dotted", color = "#555555") +
      coord_cartesian(ylim = c(-1, 1)) +
      scale_x_continuous(labels = label_number()) +
      geom_rect(aes(xmin = region$Start, xmax = region$End, ymin = -Inf, ymax = Inf),
                fill = "yellow", alpha = 0.005, inherit.aes = FALSE)

    # Create the BAF plot with highlight at CNV region
    baf_plot <- ggplot(filtered_baf) +
      geom_point(aes(x = Start, y = BAF), color = "#2a2a2a", size= 0.3) +
      theme_minimal() +
      labs(x = "Position", y = "BAF") +
      geom_hline(yintercept = 0.5, linetype = "dotted", color = "#555555") +
      coord_cartesian(ylim = c(0, 1)) +
      scale_x_continuous(labels = label_number()) +
      geom_rect(aes(xmin = region$Start, xmax = region$End, ymin = -Inf, ymax = Inf),
                fill = "yellow", alpha = 0.005, inherit.aes = FALSE)

    # Combine the plots vertically
    combined_plot <- plot_grid(lrr_plot, baf_plot, align = "v", ncol = 1, rel_heights = c(1, 1))

    # Create a filename for the current region
    output_file <- file.path(output_dir, paste0("plot_", region$Chr, "_", region$Start, "_", region$End, ".png"))

    # Save the combined plot to a PNG file
    ggsave(output_file, plot = combined_plot, width = 10, height = 8, dpi = 300)
  }
}

# Execute the appropriate function based on the mode
if (mode == "genome_plot") {
  genome_plot()
} else if (mode == "region_plot") {
  region_file <- args[4]
  region_plot(region_file)
} else {
  stop("Invalid mode. Use 'genome_plot' or 'region_plot'.")
}
