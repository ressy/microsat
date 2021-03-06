# These functions create markdown/html text for various things in report.R, for
# inclusion in the report document.

# Markdown ----------------------------------------------------------------

# k: existing kable-generated table
# grouping: logical vector with TRUE for rows to start groups with,
# optionally named
k_group_rows <- function(k, grouping) {
  idx <- which(grouping)
  labels <- names(grouping)[idx]
  if (is.null(labels))
    labels <- seq_along(idx)
  for (i in seq_along(idx)) {
    start_row <- idx[i]
    end_row <- idx[i + 1] - 1
    if (is.na(end_row))
      end_row <- length(grouping)
    k <- kableExtra::group_rows(k, labels[i], start_row, end_row)
  }
  k
}

k_row_spec <- function(k, idx.rows, ...) {
  for (idx in idx.rows) {
    k <- kableExtra::row_spec(k, idx, ...)
  }
  k
}

# convenience function for post-processing report_genotypes() output
kable_genotypes <- function(data, group_samples=FALSE) {
  bootstrap_options <- c("striped", "hover", "condensed")
  # Group rows by sample.  Assumes they're ordered already.
  if (group_samples) {
    grouping <- as.logical(c(1, diff(as.integer(factor(data$Sample)))))
    names(grouping) <- paste("Sample", data$Sample)
    data$Sample <- NULL
  }
  k <- knitr::kable(data, row.names = FALSE, format = "html")
  k <- kableExtra::kable_styling(k,
                                 bootstrap_options = bootstrap_options,
                                 full_width = FALSE)
  if (group_samples)
    k <- k_group_rows(k, grouping)
  k
}

# Write markdown tables to standard output for report_genotypes()
rmd_kable_genotypes <- function(results,
                                na.replicates="",
                                locus_chunks=NULL,
                                group_samples=FALSE,
                                closest=NULL) {
  tbl <- report_genotypes(results = results,
                   na.replicates = na.replicates,
                   closest = closest)
  if (!is.null(locus_chunks)) {
    chunk_up(data = tbl,
             locus_chunks = locus_chunks,
             kable_func = kable_genotypes,
             group_samples = group_samples)
  } else {
    cat(kable_genotypes(tbl, group_samples = group_samples))
  }
}

# convenience function for post-processing report_idents() output
kable_idents <- function(tbl, closest) {
  # Remove columns that will be represented in other ways (sample/remplicate in
  # row groupings)
  idx.remove <- match(c("Sample", "Replicate"), colnames(tbl))
  idx.remove <- idx.remove[!is.na(idx.remove)]
  tbl <- tbl[, -idx.remove]

  # Create basic table
  bootstrap_options <- c("hover", "condensed")
  k <- knitr::kable(tbl, row.names = FALSE, format = "html")
  k <- kableExtra::kable_styling(k,
                                 bootstrap_options = bootstrap_options,
                                 full_width = FALSE)

  # Group rows by sample
  obs.select <- tbl$Distance == ""
  names(obs.select) <- paste("Sample", rownames(tbl))
  k <- k_group_rows(k, obs.select)

  # Bold rows containing a single identification per sample
  # (find the original samples, and then go one farther)
  ids <- names(closest[sapply(closest, function(x) length(x) == 1)])
  idx.rows <- match(ids, rownames(tbl)) + 1
  k <- k_row_spec(k, idx.rows, bold = TRUE)

  k
}

# Write markdown tables to standard output for report_idents()
rmd_kable_idents <- function(results,
                             na.replicates,
                             locus_chunks=NULL) {
  tbl.combo <- report_idents(results,
                             closest = results$closest_matches,
                             na.replicates = na.replicates)
  if (!is.null(locus_chunks)) {
    chunk_up(data = tbl.combo,
             locus_chunks = locus_chunks,
             kable_func = kable_idents,
             closest = results$closest_matches)
  } else {
    cat(kable_idents(tbl.combo, results$closest_matches))
  }
}

# Make chunked heatmaps for the counts-per-locus table.  This does not assume
# that we have evenly-distributed numbers of samples across loci, so it will try
# to group samples into reasonably-sized sets across loci where necessary.
# max.rows: maximum number of rows in a given chunked heatmap
rmd_plot_cts_per_locus <- function(results,
                                   max.rows=30,
                                   heading_prefix="###",
                                   ...) {
  # Count samples per locus, for breaking big heatmaps into smaller chunks but
  # not splitting loci
  tbl.loci <- table(results$summary$Locus)
  tbl.loci <- tbl.loci[match(results$locus_attrs$Locus,
                             names(tbl.loci))]
  tbl.loci <- tbl.loci[!is.na(tbl.loci)]
  # Break loci into chunks to keep heatmap sizes reasonable
  loci.chunked <- split(names(tbl.loci),
                        floor(cumsum(tbl.loci) / max.rows))


  # Draw each heatmap across chunks of loci.  Written to assume there will be
  # multiple but this should work fine even if there's only one.  (Note that
  # this is all across rows, not columns like in chunk_up().)
  for (loci in loci.chunked) {
    idx <- results$summary$Locus %in% loci
    idx.row <- rownames(results$summary)[idx]
    heading <- if (length(loci) > 1) {
      paste("Samples for Loci", loci[1], "-", loci[length(loci)])
    } else {
      paste("Samples for Locus", loci[1])
    }
    if (length(loci.chunked) > 1)
      cat(paste0("\n\n", heading_prefix, " ", heading, "\n\n"))
    plot_cts_per_locus(results$cts_per_locus, idx.row, ...)
  }
}

# Insert image links to pre-rendered alignment images.
rmd_alignments <- function(results, heading_prefix="###") { # nolint
  invisible(lapply(names(results$alignments), function(loc) {
    cat(paste0("\n\n", heading_prefix, " Locus ", loc, "\n\n"))
    if (is.null(results$alignments[[loc]])) {
      cat(paste0("No sequences to align for Locus ", loc, "."))
      return()
    }
    fp <- file.path(results$config$output$dp,
                    results$config$output$dp_alignment_images,
                    paste0(loc, ".png"))
    cat(paste0("![](", fp, ")"))
  }))
}

# Util --------------------------------------------------------------------

chunk_up <- function(data, locus_chunks, kable_func, heading_prefix="###",
                     ...) {
  locus_cols_all <- allelify(locus_chunks)
  for (chunk_name in names(locus_chunks)) {
    # Remove locus columns not present in the current chunk.  It's organized
    # this way to leave the non-locus columns alone.
    # TODO support name ordering given by locus_chunks[[chunk_name]]
    locus_cols <- allelify(locus_chunks[[chunk_name]])
    # If these loci don't apply at all for the data, just skip to the next chunk
    # of loci.
    if (! any(colnames(data) %in% locus_cols)) {
      next
    }
    # Determine which loci don't apply for this chunk and remove those columns.
    locus_cols_extra <- locus_cols_all[-match(locus_cols, locus_cols_all)]
    idx.extra <- match(locus_cols_extra, colnames(data))
    idx.extra <- idx.extra[!is.na(idx.extra)]
    if (length(idx.extra) > 0) {
      tbl.chunk <- data[, -idx.extra]
    } else {
      tbl.chunk <- data
    }
    # Write the table including a heading for the loci
    cat(paste0("\n\n", heading_prefix, " ", "Loci: ", chunk_name, "\n\n"))
    cat(kable_func(tbl.chunk, ...))
  }
}

allelify <- function(loci) {
  paste(rep(unlist(loci), each = 2), c(1, 2), sep = "_")
}
