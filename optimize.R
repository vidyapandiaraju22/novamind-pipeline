# optimize.R - AI-driven content optimization
library(ellmer)
library(jsonlite)
library(dplyr)
library(glue)
library(dotenv)

load_dot_env()

# ---- Suggest next blog topics based on performance history ----
suggest_next_topics <- function(performance_path = "performance.json",
                                n_suggestions = 5) {
  
  if (!file.exists(performance_path)) {
    stop("No performance.json found. Run the pipeline first.")
  }
  
  perf <- fromJSON(performance_path, simplifyVector = TRUE)
  
  # What topics have we covered, and how did they perform per persona?
  history_summary <- as_tibble(perf) |>
    group_by(blog_title, persona) |>
    summarise(
      avg_open     = round(mean(open_rate), 3),
      avg_click    = round(mean(click_rate), 3),
      avg_unsub    = round(mean(unsub_rate), 4),
      .groups = "drop"
    ) |>
    arrange(desc(avg_click))
  
  history_text <- paste(capture.output(print(history_summary, n = Inf)), collapse = "\n")
  
  chat <- chat_anthropic(
    model = "claude-sonnet-4-5",
    api_args = list(max_tokens = 1500)
  )
  
  prompt <- glue("
You are a content strategist for NovaMind, an AI startup helping small creative
agencies automate their workflows. Below is performance data from past blog
campaigns sent to three personas: Creative Directors, Freelance Designers,
and Agency Owners.

Your job: suggest {n_suggestions} new blog topics for next week, specifically
chosen to fix engagement gaps and double down on what's working.

Past campaign performance:
{history_text}

For each suggestion, provide:
1. **Proposed blog title** (clear, specific, under 70 chars)
2. **Target persona** (which of the three it's aimed at, or 'All' if broad)
3. **3 alternative headline variants** for A/B testing
4. **Why this topic** (one sentence connecting it to the data above)

Format as clean markdown with headers for each suggestion.
")
  
  result <- chat$chat(prompt)
  writeLines(result, "next_topics.md")
  message("Saved next_topics.md")
  invisible(result)
}

# ---- Suggest headline variants for an existing topic ----
suggest_headlines <- function(topic, persona = NULL, n = 5) {
  chat <- chat_anthropic(
    model = "claude-sonnet-4-5",
    api_args = list(max_tokens = 800)
  )
  
  persona_note <- if (!is.null(persona)) {
    glue("Target persona: {persona}. Match their tone and priorities.")
  } else {
    "Write for a general audience of creative agency professionals."
  }
  
  prompt <- glue("
You are a marketing copywriter for NovaMind. Generate {n} compelling blog
headlines for this topic: '{topic}'

{persona_note}

Rules:
- Each under 70 characters
- Specific, not generic ('Cut 10 hours/week' > 'Save time')
- Mix styles: how-to, question, number-led, contrarian
- No clickbait or excessive punctuation

Return as a numbered markdown list with a one-line rationale under each.
")
  
  chat$chat(prompt)
}