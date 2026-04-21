# app.R - NovaMind Pipeline Dashboard
library(shiny)
library(shinythemes)
library(ggplot2)
library(dplyr)
library(jsonlite)
library(readr)
library(fs)

# Source the pipeline scripts
source("generate.R")
source("distribute.R")
source("analyze.R")
source("optimize.R")

# ---- UI ----
ui <- fluidPage(
  theme = shinytheme("flatly"),
  
  titlePanel(
    div(
      h1("NovaMind Content Pipeline",
         style = "color: #2c3e50; font-weight: 600; margin-bottom: 0;"),
      p("AI-powered marketing content generation, distribution, and analysis",
        style = "color: #7f8c8d; font-size: 16px; margin-top: 4px;")
    )
  ),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      
      h4("Generate Content"),
      textInput("topic",
                label = "Blog topic:",
                value = "AI in creative automation",
                width = "100%"),
      
      checkboxInput("skip_hubspot",
                    label = "Skip HubSpot sync (use cached contacts)",
                    value = TRUE),
      
      actionButton("run",
                   label = "▶ Run Full Pipeline",
                   class = "btn-primary btn-block",
                   style = "width: 100%; margin-top: 8px;"),
      
      hr(),
      
      h4("Quick Actions"),
      actionButton("suggest",
                   "💡 Suggest Next Topics",
                   class = "btn-default btn-block",
                   style = "width: 100%; margin-bottom: 6px;"),
      actionButton("refresh_perf",
                   "📊 Refresh Performance Summary",
                   class = "btn-default btn-block",
                   style = "width: 100%;"),
      
      hr(),
      
      div(style = "font-size: 13px; color: #7f8c8d;",
          p(strong("How this works:")),
          p("1. Enter a topic above"),
          p("2. Click 'Run Full Pipeline'"),
          p("3. Claude generates blog + 3 newsletters"),
          p("4. Contacts sync to HubSpot"),
          p("5. Campaigns logged + performance analyzed")
      )
    ),
    
    mainPanel(
      width = 9,
      
      tabsetPanel(
        id = "tabs",
        
        tabPanel("📝 Blog",
                 br(),
                 uiOutput("blog_ui")),
        
        tabPanel("✉️ Newsletters",
                 br(),
                 uiOutput("newsletters_ui")),
        
        tabPanel("📊 Performance",
                 br(),
                 plotOutput("perf_plot", height = "350px"),
                 br(),
                 h4("AI Performance Summary"),
                 uiOutput("ai_summary_ui")),
        
        tabPanel("💡 Next Topics",
                 br(),
                 uiOutput("next_topics_ui"))
      )
    )
  )
)

# ---- Server ----
server <- function(input, output, session) {
  
  # Reactive state
  state <- reactiveValues(
    slug = NULL,
    last_run = NULL,
    topic_suggestions = NULL
  )
  
  # Helper: read markdown file as HTML
  md_to_html <- function(path) {
    if (!file.exists(path)) return(HTML("<em>Not generated yet.</em>"))
    text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    HTML(markdown::markdownToHTML(text = text, fragment.only = TRUE))
  }
  
  # ---- Run full pipeline ----
  observeEvent(input$run, {
    withProgress(message = "Running pipeline...", value = 0, {
      
      incProgress(0.1, detail = "Generating blog and newsletters")
      run_pipeline(input$topic)
      
      if (!input$skip_hubspot) {
        incProgress(0.3, detail = "Syncing contacts to HubSpot")
        contacts <- import_contacts("contacts.csv")
      } else {
        contacts <- read_csv("contacts_imported.csv", show_col_types = FALSE)
      }
      
      incProgress(0.5, detail = "Logging campaigns")
      for (p in c("creative_director", "freelance_designer", "agency_owner")) {
        log_campaign(input$topic, p, contacts)
      }
      
      incProgress(0.75, detail = "Simulating performance")
      simulate_performance()
      
      incProgress(0.95, detail = "Generating AI summary")
      summarize_performance()
    })
    
    state$slug <- slugify(input$topic)
    state$last_run <- Sys.time()
    
    showNotification("Pipeline complete ✓", type = "message", duration = 4)
  })
  
  # ---- Suggest next topics ----
  observeEvent(input$suggest, {
    withProgress(message = "Analyzing performance history...", {
      result <- suggest_next_topics()
      state$topic_suggestions <- result
    })
    updateTabsetPanel(session, "tabs", selected = "💡 Next Topics")
  })
  
  # ---- Refresh performance summary ----
  observeEvent(input$refresh_perf, {
    withProgress(message = "Regenerating summary...", {
      summarize_performance()
      state$last_run <- Sys.time()
    })
    updateTabsetPanel(session, "tabs", selected = "📊 Performance")
  })
  
  # ---- Blog output ----
  output$blog_ui <- renderUI({
    req(state$slug)
    md_to_html(path("content", state$slug, "blog.md"))
  })
  
  # ---- Newsletters output ----
  output$newsletters_ui <- renderUI({
    req(state$slug)
    
    persona_labels <- list(
      creative_director  = "🎨 Creative Director",
      freelance_designer = "💻 Freelance Designer",
      agency_owner       = "💼 Agency Owner"
    )
    
    tabs <- lapply(names(persona_labels), function(p) {
      tabPanel(
        persona_labels[[p]],
        br(),
        md_to_html(path("content", state$slug, paste0("newsletter_", p, ".md")))
      )
    })
    
    do.call(tabsetPanel, tabs)
  })
  
  # ---- Performance plot ----
  output$perf_plot <- renderPlot({
    state$last_run  # reactive dependency
    req(file.exists("performance.json"))
    
    perf <- fromJSON("performance.json", simplifyVector = TRUE) |>
      as_tibble() |>
      group_by(persona) |>
      summarise(
        open_rate  = mean(open_rate),
        click_rate = mean(click_rate),
        .groups = "drop"
      ) |>
      tidyr::pivot_longer(c(open_rate, click_rate),
                          names_to = "metric", values_to = "rate")
    
    ggplot(perf, aes(x = persona, y = rate, fill = metric)) +
      geom_col(position = "dodge", width = 0.65) +
      geom_text(aes(label = scales::percent(rate, accuracy = 0.1)),
                position = position_dodge(0.65), vjust = -0.4, size = 3.5) +
      scale_y_continuous(labels = scales::percent_format(),
                         expand = expansion(mult = c(0, 0.15))) +
      scale_fill_manual(values = c("open_rate" = "#3498db",
                                   "click_rate" = "#2ecc71"),
                        labels = c("Click rate", "Open rate")) +
      labs(title = "Average campaign performance by persona",
           x = NULL, y = NULL, fill = NULL) +
      theme_minimal(base_size = 13) +
      theme(legend.position = "top",
            panel.grid.major.x = element_blank(),
            plot.title = element_text(face = "bold"))
  })
  
  # ---- AI Summary ----
  output$ai_summary_ui <- renderUI({
    state$last_run  # reactive dependency
    if (!file.exists("performance.json")) {
      return(HTML("<em>Run the pipeline first to see a summary.</em>"))
    }
    summary_text <- summarize_performance()
    HTML(markdown::markdownToHTML(text = summary_text, fragment.only = TRUE))
  })
  
  # ---- Next topics ----
  output$next_topics_ui <- renderUI({
    if (is.null(state$topic_suggestions)) {
      return(HTML("<em>Click 'Suggest Next Topics' in the sidebar to generate recommendations based on your campaign history.</em>"))
    }
    HTML(markdown::markdownToHTML(text = state$topic_suggestions, fragment.only = TRUE))
  })
}

# ---- Launch ----
shinyApp(ui = ui, server = server)