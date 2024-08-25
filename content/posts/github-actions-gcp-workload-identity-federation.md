---
title: 'Configuring GCP Workload Identity Federation For GitHub Actions'
date: "2024-08-25T09:32:51-07:00"
categories:
  - Cloud
tags:
  - GCP
  - GitHub Actions
  - Terraform
---

I recently needed to push container images and Helm charts to [Artifact Registry](https://cloud.google.com/artifact-registry) and wanted to use GitHub Actions. Looking around I found [this action](https://github.com/marketplace/actions/authenticate-to-google-cloud) and this blog post describing [how to use service accounts and keyless authentication using workload identity federation](https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions). Luckily, this blog post described all the individual steps for setting this up using the `gcloud` CLI so it was straightforward adapting it to my Terraform workflow.

## Terraform Configuration

See the Google blog post for more details on how the authentication actually works, here is the Terraform configuration:

```hcl
locals {
  # Your GCP project id
  project_id = "<your google cloud project id>"

  # The GitHub org (or username) where the actions will run
  github_org = "<your org or username>"

  # The individual repos that will be running actions that need to authenticate
  github_repos = [
    "<your repo>"
  ]

  # IAM roles to assign to the Service Account
  roles = [
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer",
  ]
}

# Create the Service Account
resource "google_service_account" "gh_actions_sa" {
  account_id   = "gh-actions"
  display_name = "Service Account for GitHub Actions to push container images and Helm charts to Artifact Registry"
}

# Create a workload identity pool to associate the service account with
resource "google_iam_workload_identity_pool" "github" {
  project                   = local.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "github-actions"
  description               = "For GitHub Actions authentication"
}

# Create a workload identity provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "github-provider"
  description                        = "OIDC identity pool provider for execute GitHub Actions"
  # See. https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token
  attribute_condition = "assertion.repository_owner == '${local.github_org}'"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  oidc {
    issuer_uri        = "https://token.actions.githubusercontent.com"
    allowed_audiences = []
  }
}

# Allow the service account to authenticate with a GitHub action from each of the declared repos
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = toset(local.github_repos)

  service_account_id = google_service_account.gh_actions_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_org}/${each.value}"
}

# Attach the roles that the Service Account will need
resource "google_project_iam_member" "sa_roles" {
  for_each = toset(local.roles)

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gh_actions_sa.email}"
}

# This is the value you'll need for the GitHub Action authenticate step
output "service_account_email" {
  description = "The Service Account email"
  value       = google_service_account.gh_actions_sa.email
}

# This is the value you'll need for the GitHub Action authenticate step
output "workload_identity_pool_name" {
  description = "Workload Identity Pood Provider ID"
  value       = google_iam_workload_identity_pool_provider.github.name
}

```

## GitHub Action Configuration

Once you provision all of the resources you will want to take the outputs and set them up as secrets for your GitHub Actions.
This will then allow you to configure the following steps in your Actions:

```yaml
name: Auth Example

jobs:
  example:
    runs-on: ubuntu-latest

    # Required permissions for authenticating with GCP
    # See https://github.com/google-github-actions/auth for details
    permissions:
      contents: 'read'
      id-token: 'write'

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      #
      - name: Log in to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          service_account: '${{ secrets.SERVICE_ACCOUNT_EMAIL }}'
          workload_identity_provider: '${{ secrets.WORKLOAD_IDENTITY_PROVIDER }}'

```

With these steps you can authenticate to your GCP project with GitHub Actions in a scoped manner. There is additional hardening that can be done, but this is a starter for that.
