% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/survival_diagnostics_app.R
\name{.run_survival_diagnostics}
\alias{.run_survival_diagnostics}
\title{Run Survival Diagnostics for Pilot Data}
\usage{
.run_survival_diagnostics(
  pilot_data,
  time_var,
  status_var,
  arm_var,
  strata_var = NULL
)
}
\arguments{
\item{pilot_data}{A data frame containing the pilot data with survival information.}

\item{time_var}{A string specifying the name of the time variable in the pilot data.}

\item{status_var}{A string specifying the name of the status variable in the pilot data (1 for event, 0 for censored).}

\item{arm_var}{A string specifying the name of the treatment arm variable in the pilot data.}

\item{strata_var}{An optional string specifying the name of the stratification variable in the pilot data.}
}
\description{
This function performs survival diagnostics on pilot data, including a log-rank test and Kaplan-Meier plot.
}
\details{
Run Survival Diagnostics for Pilot Data
}
\keyword{internal}
