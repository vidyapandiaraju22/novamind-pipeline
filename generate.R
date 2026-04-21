# generate.R
library(ellmer)
library(glue)
library(dotenv)
library(fs)

load_dot_env()  # loads .env into the environment

PERSONAS <- list(
  creative_director = list(
    name = "Creative Director",
    description = "A senior creative at a mid-size agency who cares about team output quality, creative vision, and freeing their team from repetitive work.",
    tone = "inspiring and strategic, light on jargon"
  ),
  freelance_designer = list(
    name = "Freelance Designer",
    description = "An independent designer juggling multiple clients who cares about saving time on admin work and focusing on actual design.",
    tone = "casual, practical, time-focused"
  ),
  agency_owner = list(
    name = "Agency Owner",
    description = "The founder or operations lead of a small agency who cares about ROI, margins, team efficiency, and scaling without more headcount.",
    tone = "direct, business-focused, metrics-oriented"
  )
)

# Fresh chat session for each call (no memory between calls)
new_chat <- function(max_tokens = 2000) {
  chat_anthropic(
    model = "claude-sonnet-4-5",
    params = params(max_tokens = max_tokens)
  )
}

generate_blog <- function(topic) {
  chat <- new_chat(max_tokens = 2000)
  prompt <- glue("
You are a content writer for NovaMind, an early-stage AI startup that helps small creative agencies automate their daily workflows (think Notion + Zapier + ChatGPT combined).

Write a blog post about: '{topic}'

Requirements:
- MINIMUM 400 words, TARGET 500 words for the post itself
- Start with '## Outline' containing 4-5 bullet points
- Then '## Post' with the full 400-600 word post
- Tone: smart, practical, approachable - not hypey
- Include at least one concrete example or mini case study
- End with a short CTA inviting readers to try NovaMind

Return ONLY the markdown content, no preamble.

Return ONLY the markdown content, no preamble.
")
  chat$chat(prompt)
}

generate_newsletter <- function(blog_text, persona_key) {
  persona <- PERSONAS[[persona_key]]
  chat <- new_chat(max_tokens = 800)
  prompt <- glue("
You are a marketing copywriter for NovaMind. Below is a blog post. Rewrite it as a ~150-word newsletter email tailored for this persona:

Persona: {persona$name}
About them: {persona$description}
Tone: {persona$tone}

Include:
- A subject line (prefix with 'Subject: ')
- A greeting
- A short hook that speaks to what this persona cares about
- 2-3 key takeaways from the blog, rewritten for this audience
- A clear CTA to read the full post

Blog post:
---
{blog_text}
---

Return ONLY the newsletter content in markdown.
")
  chat$chat(prompt)
}

slugify <- function(text) {
  text <- tolower(text)
  text <- gsub("[^a-z0-9]+", "-", text)
  text <- gsub("^-|-$", "", text)
  substr(text, 1, 60)
}

run_pipeline <- function(topic = "AI in creative automation") {
  slug <- slugify(topic)
  out_dir <- path("content", slug)
  dir_create(out_dir)
  
  message("Generating blog for: ", topic)
  blog <- generate_blog(topic)
  writeLines(blog, path(out_dir, "blog.md"))
  
  for (persona_key in names(PERSONAS)) {
    message("Generating newsletter for: ", persona_key)
    newsletter <- generate_newsletter(blog, persona_key)
    writeLines(newsletter, path(out_dir, paste0("newsletter_", persona_key, ".md")))
  }
  
  message("Done.")
}