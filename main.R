# main.R - single entry point for the full pipeline

# README import_contacts() is idempotent — re-running it on existing contacts returns HubSpot 409 Conflict, which the script intentionally treats as a "skip" rather than a failure. This is visible in the HubSpot API logs as expected 4xx responses.


source("generate.R")
source("distribute.R")
source("analyze.R")

run_full_pipeline <- function(topic = "AI in creative automation",
                              skip_hubspot = FALSE) {
  message("\n=== NovaMind Content Pipeline ===")
  message("Topic: ", topic, "\n")
  
  # ---- Phase 1: Generate content ----
  message(">>> Phase 1: Generating content...")
  run_pipeline(topic)
  
  # ---- Phase 2a: Import contacts (idempotent - skips existing) ----
  if (!skip_hubspot) {
    message("\n>>> Phase 2a: Syncing contacts to HubSpot...")
    contacts <- import_contacts("contacts.csv")
  } else {
    message("\n>>> Phase 2a: Skipping HubSpot sync (reading local cache)...")
    contacts <- readr::read_csv("contacts_imported.csv", show_col_types = FALSE)
  }
  
  # ---- Phase 2b: Log campaigns per persona ----
  message("\n>>> Phase 2b: Logging campaigns...")
  for (p in c("creative_director", "freelance_designer", "agency_owner")) {
    log_campaign(topic, p, contacts)
  }
  
  # ---- Phase 3: Simulate + analyze performance ----
  message("\n>>> Phase 3: Simulating performance...")
  simulate_performance()
  
  message("\n>>> Phase 3: Generating AI summary...")
  summary <- summarize_performance()
  
  message("\n=== Pipeline complete ===")
  message("Outputs:")
  message("  - content/<slug>/   (blog + newsletters)")
  message("  - contacts_imported.csv")
  message("  - campaigns.json")
  message("  - performance.json")
  
  invisible(summary)
}

# Run from command line: Rscript main.R "Your topic"
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  topic <- if (length(args) > 0) args[1] else "AI in creative automation"
  run_full_pipeline(topic)
}