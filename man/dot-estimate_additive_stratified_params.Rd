% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/additive_stratified_analytical_app.R
\name{.estimate_additive_stratified_params}
\alias{.estimate_additive_stratified_params}
\title{Internal Helper to Estimate Additive Stratified Model Parameters}
\usage{
.estimate_additive_stratified_params(
  pilot_data,
  time_var,
  status_var,
  arm_var,
  strata_var,
  linear_terms,
  L
)
}
\value{
A list containing \code{beta_effect} (the estimated treatment effect) and
\code{se_beta_n1} (the standard error for a sample size of 1).
}
\description{
This internal function contains the common logic for estimating the
treatment effect and its variance from pilot data for the additive stratified model.
It is called by both the power and sample size calculation functions to avoid
code duplication.
}
\keyword{internal}
