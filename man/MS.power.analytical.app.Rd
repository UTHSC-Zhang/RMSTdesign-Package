% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/multiplicative_stratified_analytical_app.R
\name{MS.power.analytical.app}
\alias{MS.power.analytical.app}
\title{Analyze Power for a Multiplicative Stratified RMST Model (Analytic)}
\usage{
MS.power.analytical.app(
  pilot_data,
  time_var,
  status_var,
  arm_var,
  strata_var,
  sample_sizes,
  linear_terms = NULL,
  L,
  alpha = 0.05
)
}
\arguments{
\item{sample_sizes}{A numeric vector of sample sizes \emph{per stratum} to calculate power for.}

\item{alpha}{The significance level (Type I error rate).}
}
\value{
A list containing results.
}
\description{
Performs power analysis for a multiplicative, stratified RMST model using an
analytic method based on the work of Wang et al. (2019).
}
\keyword{internal}
