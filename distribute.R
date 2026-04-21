# distribute.R
library(httr2)
library(readr)
library(dplyr)
library(dotenv)
library(jsonlite)
library(purrr)

load_dot_env()
HUBSPOT_BASE <- "https://api.hubapi.com"

# ---- 1. Sanity check: verify your token works ----
check_token <- function() {
  req <- request(paste0(HUBSPOT_BASE, "/crm/v3/objects/contacts")) |>
    req_auth_bearer_token(Sys.getenv("HUBSPOT_TOKEN")) |>
    req_url_query(limit = 1)
  resp <- req_perform(req)
  if (resp_status(resp) == 200) {
    message("HubSpot token works.")
    TRUE
  } else {
    message("HubSpot token failed: ", resp_status(resp))
    FALSE
  }
}

# ---- 2. Create or update a single contact ----
create_contact <- function(email, firstname, lastname, persona) {
  req <- request(paste0(HUBSPOT_BASE, "/crm/v3/objects/contacts")) |>
    req_auth_bearer_token(Sys.getenv("HUBSPOT_TOKEN")) |>
    req_headers("Content-Type" = "application/json") |>
    req_body_json(list(
      properties = list(
        email = email,
        firstname = firstname,
        lastname = lastname,
        persona = persona
      )
    )) |>
    req_error(is_error = function(resp) FALSE)
  
  resp <- req_perform(req)
  status <- resp_status(resp)
  body <- resp_body_json(resp)
  
  if (status == 201) {
    message(sprintf("  Created %s (id: %s)", email, body$id))
    return(body$id)
  } else if (status == 409) {
    message(sprintf("  Already exists: %s (skipping)", email))
    return(NA_character_)
  } else {
    message(sprintf("  ERROR %d for %s: %s", status, email, body$message))
    return(NA_character_)
  }
}

# ---- 3. Import contacts from CSV ----
import_contacts <- function(csv_path = "contacts.csv") {
  contacts <- read_csv(csv_path, show_col_types = FALSE)
  message("Importing ", nrow(contacts), " contacts to HubSpot...")
  
  ids <- pmap_chr(contacts, function(firstname, lastname, email, persona) {
    create_contact(email, firstname, lastname, persona)
  })
  
  contacts$hubspot_id <- ids
  write_csv(contacts, "contacts_imported.csv")
  message("Saved contacts_imported.csv")
  contacts
}

# ---- 4. Update last_campaign property on a single contact ----
update_contact_campaign <- function(contact_id, campaign_id, topic, persona) {
  if (is.na(contact_id) || contact_id == "") return(NA_character_)
  
  value <- sprintf("%s | %s | %s | %s",
                   campaign_id,
                   format(Sys.time(), "%Y-%m-%d"),
                   persona,
                   topic)
  
  req <- request(paste0(HUBSPOT_BASE, "/crm/v3/objects/contacts/", contact_id)) |>
    req_auth_bearer_token(Sys.getenv("HUBSPOT_TOKEN")) |>
    req_headers("Content-Type" = "application/json") |>
    req_method("PATCH") |>
    req_body_json(list(
      properties = list(last_campaign = value)
    )) |>
    req_error(is_error = function(resp) FALSE)
  
  resp <- req_perform(req)
  if (resp_status(resp) == 200) {
    return(value)
  } else {
    message(sprintf("  Failed to update contact %s: %d", contact_id, resp_status(resp)))
    return(NA_character_)
  }
}

# ---- 5. Log a campaign (per persona) ----
log_campaign <- function(topic, persona, contacts_df) {
  persona_contacts <- contacts_df |> filter(persona == !!persona)
  campaign_id <- paste0("cmp_", format(Sys.time(), "%Y%m%d%H%M%S"), "_", persona)
  
  message(sprintf("Updating %d contacts in HubSpot for %s...",
                  nrow(persona_contacts), persona))
  for (id in persona_contacts$hubspot_id) {
    update_contact_campaign(id, campaign_id, topic, persona)
  }
  
  entry <- list(
    campaign_id = campaign_id,
    blog_title = topic,
    persona = persona,
    newsletter_file = paste0("newsletter_", persona, ".md"),
    contact_count = nrow(persona_contacts),
    contact_ids = persona_contacts$hubspot_id,
    sent_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
  )
  
  log_path <- "campaigns.json"
  existing <- if (file.exists(log_path)) {
    fromJSON(log_path, simplifyVector = FALSE)
  } else list()
  existing[[length(existing) + 1]] <- entry
  write_json(existing, log_path, pretty = TRUE, auto_unbox = TRUE)
  
  message(sprintf("Logged campaign for %s (%d contacts)",
                  persona, nrow(persona_contacts)))
  entry
}

# ---- 6. Look up HubSpot IDs for all contacts by email ----
refresh_contact_ids <- function(csv_path = "contacts.csv") {
  contacts <- read_csv(csv_path, show_col_types = FALSE)
  message("Looking up HubSpot IDs for ", nrow(contacts), " contacts...")
  
  ids <- purrr::map_chr(contacts$email, function(email) {
    req <- request(paste0(HUBSPOT_BASE, "/crm/v3/objects/contacts/", email)) |>
      req_auth_bearer_token(Sys.getenv("HUBSPOT_TOKEN")) |>
      req_url_query(idProperty = "email") |>
      req_error(is_error = function(resp) FALSE)
    
    resp <- req_perform(req)
    if (resp_status(resp) == 200) {
      body <- resp_body_json(resp)
      message(sprintf("  Found %s -> %s", email, body$id))
      return(body$id)
    } else {
      message(sprintf("  Not found: %s (%d)", email, resp_status(resp)))
      return(NA_character_)
    }
  })
  
  contacts$hubspot_id <- ids
  write_csv(contacts, "contacts_imported.csv")
  message("Refreshed contacts_imported.csv")
  contacts
}

# ---- 7. Show full campaign history for a given contact ID ----
contact_history <- function(contact_id, campaigns_path = "campaigns.json") {
  campaigns <- fromJSON(campaigns_path, simplifyVector = FALSE)
  
  received <- Filter(function(c) contact_id %in% c$contact_ids, campaigns)
  
  if (length(received) == 0) {
    message("No campaigns found for contact ", contact_id)
    return(invisible(NULL))
  }
  
  history <- data.frame(
    campaign_id = sapply(received, `[[`, "campaign_id"),
    blog_title  = sapply(received, `[[`, "blog_title"),
    persona     = sapply(received, `[[`, "persona"),
    sent_at     = sapply(received, `[[`, "sent_at"),
    stringsAsFactors = FALSE
  )
  
  history
}