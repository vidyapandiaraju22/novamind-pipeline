# analyze.R
library(ellmer)
library(dplyr)
library(jsonlite)
library(glue)
library(dotenv)

load_dot_env()

# ---- 1. Simulate per-persona performance with realistic randomness ----
simulate_performance <- function(campaigns_path = "campaigns.json") {
  campaigns <- fromJSON(campaigns_path, simplifyVector = FALSE)
  
  # Base rates (realistic for B2B newsletters)
  base_rates <- list(
    creative_director  = list(open = 0.38, click = 0.09, unsub = 0.004),
    freelance_designer = list(open = 0.45, click = 0.13, unsub = 0.008),
    agency_owner       = list(open = 0.29, click = 0.05, unsub = 0.003)
  )
  
  set.seed(NULL)  # fresh randomness each run
  results <- lapply(campaigns, function(c) {
    r <- base_rates[[c$persona]]
    list(
      campaign_id   = c$campaign_id,
      persona       = c$persona,
      blog_title    = c$blog_title,
      contact_count = c$contact_count,
      open_rate     = round(max(0, r$open  + rnorm(1, 0, 0.04)), 3),
      click_rate    = round(max(0, r$click + rnorm(1, 0, 0.02)), 3),
      unsub_rate    = round(max(0, r$unsub + rnorm(1, 0, 0.002)), 4),
      sent_at       = c$sent_at
    )
  })
  
  write_json(results, "performance.json", pretty = TRUE, auto_unbox = TRUE)
  message("Saved performance.json (", length(results), " campaigns)")
  results
}

# ---- 2. Summary stats with dplyr ----
performance_summary <- function(performance_path = "performance.json") {
  perf <- fromJSON(performance_path, simplifyVector = TRUE)
  as_tibble(perf) |>
    group_by(persona) |>
    summarise(
      campaigns    = n(),
      avg_open     = round(mean(open_rate), 3),
      avg_click    = round(mean(click_rate), 3),
      avg_unsub    = round(mean(unsub_rate), 4),
      total_contacts = sum(contact_count),
      .groups = "drop"
    ) |>
    arrange(desc(avg_click))
}

# ---- 3. AI-powered performance summary ----
summarize_performance <- function(performance_path = "performance.json") {
  summary_df <- performance_summary(performance_path)
  perf <- fromJSON(performance_path, simplifyVector = TRUE)
  
  summary_text <- paste(capture.output(print(summary_df)), collapse = "\n")
  raw_json <- toJSON(perf, pretty = TRUE, auto_unbox = TRUE)
  
  chat <- chat_anthropic(
    model = "claude-sonnet-4-5",
    api_args = list(max_tokens = 1000)
  )
  
  prompt <- glue("
You are a marketing analyst for NovaMind. Below is campaign performance data
segmented by persona. Write a brief 2-3 paragraph analyst summary:

- Call out which persona is performing best and worst, and by how much
- Suggest 3 concrete, actionable recommendations for next week's content
- Keep it tight and data-driven, no filler

Summary by persona:
{summary_text}

Raw per-campaign data:
{raw_json}
")
  
  cat("\n--- AI PERFORMANCE SUMMARY ---\n\n")
  result <- chat$chat(prompt)
  cat("\n\n")
  invisible(result)
}