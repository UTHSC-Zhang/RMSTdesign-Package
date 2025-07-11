#' @title Analyze Power for a Stratified Additive RMST Model (Analytic)
#' @description Performs power analysis for a stratified, additive RMST model using the
#'   analytic variance estimator based on the method of Zhang & Schaubel (2024).
#'
#' @details
#' This function implements the power calculation for the semiparametric additive
#' model for RMST, given by \eqn{\mu_{ij} = \mu_{0j} + \beta'Z_i}, where `i` is the
#' subject and `j` is the stratum.
#'
#' The method uses Inverse Probability of Censoring Weighting (IPCW), where weights are
#' derived from a stratified Cox model on the censoring times. The regression
#' coefficient \eqn{\hat{\beta}} is estimated using a closed-form solution that
#' involves centering the covariates and RMST values within each stratum.
#'
#' Power is determined analytically from the asymptotic sandwich variance of \eqn{\hat{\beta}}.
#' This implementation uses a robust variance estimator of the form
#' \eqn{A_n^{-1} B_n (A_n^{-1})'}, where \eqn{A_n} and \eqn{B_n} are empirical
#' estimates of the variance components.
#'
#' @param pilot_data A `data.frame` containing pilot study data.
#' @param time_var A character string for the time-to-event variable.
#' @param status_var A character string for the event status variable (1=event, 0=censored).
#' @param arm_var A character string for the treatment arm variable (1=treatment, 0=control).
#' @param strata_var A character string for the stratification variable.
#' @param sample_sizes A numeric vector of sample sizes *per stratum* to calculate power for.
#' @param linear_terms An optional character vector of other covariate names.
#' @param L The numeric value for the RMST truncation time.
#' @param alpha The significance level (Type I error rate).
#'
#' @return A `list` containing:
#' \item{results_data}{A `data.frame` with specified sample sizes and corresponding powers.}
#' \item{results_plot}{A `ggplot` object visualizing the power curve.}
#' @export
#' @importFrom stats as.formula complete.cases lm na.omit pnorm qnorm quantile sd vcov weighted.mean predict
#' @importFrom survival Surv coxph basehaz
#' @importFrom ggplot2 ggplot aes geom_line geom_point labs theme_minimal ylim
#' @importFrom dplyr group_by summarise across all_of mutate select left_join
#' @importFrom magrittr %>%
#'
#' @examples
#' set.seed(123)
#' pilot_df_strat <- data.frame(
#'  time = rexp(150, 0.1),
#'  status = rbinom(150, 1, 0.8),
#'  arm = rep(0:1, each = 75),
#'  region = factor(rep(c("A", "B", "C"), each = 50)),
#'  age = rnorm(150, 60, 10)
#' )
#' # Introduce an additive treatment effect
#' pilot_df_strat$time[pilot_df_strat$arm == 1] <-
#'   pilot_df_strat$time[pilot_df_strat$arm == 1] + 1.5
#'
#' power_results <- additive.power.analytical(
#'   pilot_data = pilot_df_strat,
#'   time_var = "time", status_var = "status", arm_var = "arm", strata_var = "region",
#'   sample_sizes = c(100, 150, 200),
#'   linear_terms = "age",
#'   L = 12
#' )
#' print(power_results$results_data)
#' print(power_results$results_plot)
#'
additive.power.analytical <- function(pilot_data, time_var, status_var, arm_var, strata_var,
                                      sample_sizes, linear_terms = NULL, L, alpha = 0.05) {

   # --- 1. Prepare Data and Calculate IPCW Weights ---
   cat("--- Estimating parameters from pilot data... ---\n")
   covariates <- c(arm_var, linear_terms)
   all_vars <- c(time_var, status_var, strata_var, covariates)
   df <- pilot_data[stats::complete.cases(pilot_data[, all_vars]), ]
   n_pilot <- nrow(df)

   df$Y_rmst <- pmin(df[[time_var]], L)
   df$is_event <- df[[status_var]] == 1

   cens_formula <- stats::as.formula(paste0("survival::Surv(Y_rmst, is_event == 0) ~ ",
                                            paste(covariates, collapse = " + "),
                                            " + survival::strata(", strata_var, ")"))
   fit_cens <- survival::coxph(cens_formula, data = df, ties = "breslow")

   bh_cens <- survival::basehaz(fit_cens, centered = FALSE)
   df$H_cens <- 0
   unique_strata_from_bh <- unique(bh_cens$strata)
   for(st in unique(df[[strata_var]])){
      st_label <- paste0(strata_var, "=", st)
      is_stratum <- df[[strata_var]] == st
      if (st_label %in% unique_strata_from_bh) {
         is_bh_stratum <- bh_cens$strata == st_label
         if(sum(is_bh_stratum) > 0){
            H_st <- stats::stepfun(bh_cens$time[is_bh_stratum], c(0, bh_cens$hazard[is_bh_stratum]))(df$Y_rmst[is_stratum])
            df$H_cens[is_stratum] <- H_st
         }
      }
   }
   df$weights <- exp(df$H_cens * exp(stats::predict(fit_cens, newdata=df, type="lp", reference="zero")))
   df$weights[!df$is_event] <- 0
   finite_weights <- df$weights[is.finite(df$weights) & df$weights > 0]
   if (length(finite_weights) > 0) {
      weight_cap <- stats::quantile(finite_weights, probs = 0.99, na.rm = TRUE)
      df$weights[df$weights > weight_cap] <- weight_cap
   }
   df$weights[!is.finite(df$weights)] <- 0

   # --- 2. Estimate Beta via Stratum-Centering ---
   cat("--- Estimating additive effect via stratum-centering... ---\n")
   vars_to_center <- c("Y_rmst", covariates)

   stratum_means <- df %>%
      dplyr::group_by(.data[[strata_var]]) %>%
      dplyr::summarise(
         dplyr::across(
            dplyr::all_of(vars_to_center),
            ~ weighted.mean(.x, w = weights, na.rm = TRUE)
         ),
         .groups = 'drop'
      )
   names(stratum_means) <- c(strata_var, paste0(vars_to_center, "_mean"))

   df_centered <- df %>%
      dplyr::left_join(stratum_means, by = strata_var)

   for (cov in vars_to_center) {
      df_centered[[paste0(cov, "_tilde")]] <- df_centered[[cov]] - df_centered[[paste0(cov, "_mean")]]
   }

   Z_tilde <- as.matrix(df_centered[, paste0(covariates, "_tilde")])
   Y_tilde <- df_centered[["Y_rmst_tilde"]]
   W <- df_centered$weights

   A_hat_num <- crossprod(Z_tilde * sqrt(W))
   dimnames(A_hat_num) <- list(covariates, covariates)
   A_hat <- A_hat_num / n_pilot

   # CORRECTED: Add error handling for singular matrix
   A_hat_inv <- tryCatch({
      solve(A_hat)
   }, error = function(e) {
      stop("The covariate matrix (A_hat) is singular and cannot be inverted.\nThis may be caused by a lack of variation in the covariates among subjects with an event within one or more strata.\nPlease inspect the pilot data for issues like perfect separation.", call. = FALSE)
   })

   beta_hat <- (A_hat_inv / n_pilot) %*% (t(Z_tilde * W) %*% Y_tilde)
   rownames(beta_hat) <- covariates
   beta_effect <- beta_hat[arm_var, 1]

   # --- 3. Calculate Asymptotic Sandwich Variance ---
   cat("--- Calculating asymptotic variance... ---\n")
   mu0_hats <- stratum_means %>%
      dplyr::mutate(
         Z_matrix = as.matrix(dplyr::select(., dplyr::all_of(paste0(covariates, "_mean")))),
         mu0_hat = .data[["Y_rmst_mean"]] - Z_matrix %*% beta_hat
      ) %>%
      dplyr::select(dplyr::all_of(strata_var), mu0_hat)

   df_final <- df_centered %>% dplyr::left_join(mu0_hats, by = strata_var)
   Z_matrix <- as.matrix(df_final[, covariates])

   df_final$residuals <- df_final$Y_rmst - (df_final$mu0_hat + as.vector(Z_matrix %*% beta_hat))

   epsilon <- apply(Z_tilde, 2, function(z_col) z_col * W * df_final$residuals)
   B_hat <- crossprod(epsilon) / n_pilot
   dimnames(B_hat) <- list(covariates, covariates)

   V_hat_n <- A_hat_inv %*% B_hat %*% t(A_hat_inv)

   var_beta_pilot <- V_hat_n[arm_var, arm_var] / n_pilot
   var_beta_n1 <- var_beta_pilot * n_pilot
   se_beta_n1 <- sqrt(var_beta_n1)

   # --- 4. Calculate Power ---
   cat("--- Calculating power for specified sample sizes... ---\n")
   z_alpha <- stats::qnorm(1 - alpha / 2)
   n_strata <- length(unique(df[[strata_var]]))
   power_values <- sapply(sample_sizes, function(n_per_stratum) {
      total_n <- n_per_stratum * n_strata
      se_final <- se_beta_n1 / sqrt(total_n)
      power <- stats::pnorm( (abs(beta_effect) / se_final) - z_alpha )
      return(power)
   })

   results_df <- data.frame(N_per_Stratum = sample_sizes, Power = power_values)

   # --- 5. Plot and Return ---
   p <- ggplot2::ggplot(results_df, ggplot2::aes(x = N_per_Stratum, y = Power)) +
      ggplot2::geom_line(color = "#0072B2", linewidth = 1) +
      ggplot2::geom_point(color = "#0072B2", size = 3) +
      ggplot2::labs(
         title = "Analytic Power Curve: Additive Stratified RMST Model",
         subtitle = "Based on stratum-centered estimating equations.",
         x = "Sample Size Per Stratum", y = "Estimated Power"
      ) +
      ggplot2::ylim(0, 1) + ggplot2::theme_minimal()

   return(list(results_data = results_df, results_plot = p))
}


#' @title Find Sample Size for a Stratified Additive RMST Model (Analytic)
#' @description Calculates the required sample size for a target power using the analytic
#'   method for a stratified, additive RMST model.
#'
#' @details
#' This function performs an iterative search for the sample size required to
#' achieve a specified `target_power`. It uses the same underlying theory as
#' `additive.power.analytical`, based on stratum-centering of covariates. It performs
#' a one-time estimation of the additive treatment effect and its asymptotic variance
#' from the pilot data, then uses these parameters in an analytic formula to
#' efficiently find the required sample size.
#'
#' @param pilot_data A `data.frame` containing pilot study data.
#' @param time_var A character string for the time-to-event variable.
#' @param status_var A character string for the event status variable (1=event, 0=censored).
#' @param arm_var A character string for the treatment arm variable (1=treatment, 0=control).
#' @param strata_var A character string for the stratification variable.
#' @param target_power A single numeric value for the desired power.
#' @param linear_terms An optional character vector of other covariate names.
#' @param L The numeric value for the RMST truncation time.
#' @param alpha The significance level (Type I error rate).
#' @param n_start The starting sample size *per stratum* for the search.
#' @param n_step The increment in sample size at each step of the search.
#' @param max_n_per_arm The maximum sample size *per stratum* to search up to.
#'
#' @return A `list` containing:
#' \item{results_data}{A `data.frame` with the target power and required sample size.}
#' \item{results_plot}{A `ggplot` object visualizing the search path.}
#' \item{results_summary}{A `data.frame` summarizing the estimated treatment effect.}
#' @export
#' @importFrom stats as.formula complete.cases lm na.omit pnorm qnorm quantile sd vcov weighted.mean predict
#' @importFrom survival Surv coxph basehaz
#' @importFrom ggplot2 ggplot aes geom_line geom_point geom_hline geom_vline labs theme_minimal
#' @importFrom knitr kable
#' @importFrom dplyr group_by summarise across all_of mutate select left_join
#' @importFrom magrittr %>%
#' @examples
#' set.seed(123)
#' pilot_df_strat <- data.frame(
#'  time = rexp(150, 0.1),
#'  status = rbinom(150, 1, 0.8),
#'  arm = rep(0:1, each = 75),
#'  region = factor(rep(c("A", "B", "C"), each = 50)),
#'  age = rnorm(150, 60, 10)
#' )
#' # Introduce an additive treatment effect
#' pilot_df_strat$time[pilot_df_strat$arm == 1] <-
#'   pilot_df_strat$time[pilot_df_strat$arm == 1] + 1.5
#'
#'   # Find the required sample size per stratum for 80% power
#'   ss_results <- additive.ss.analytical(
#'     pilot_data = pilot_df_strat,
#'     time_var = "time", status_var = "status",
#'     arm_var = "arm", strata_var = "region",
#'     target_power = 0.50,
#'     L = 18, #
#'     n_start = 200,
#'     n_step = 50,
#'     max_n_per_arm = 1000
#'   )
#'   print(ss_results$results_data)
#'   print(ss_results$results_plot)
additive.ss.analytical <- function(pilot_data, time_var, status_var, arm_var, strata_var,
                                   target_power, linear_terms = NULL, L, alpha = 0.05,
                                   n_start = 50, n_step = 25, max_n_per_arm = 2000) {

   # --- 1. Estimate Parameters and Variance from Pilot Data (One Time) ---
   cat("--- Estimating parameters from pilot data for analytic search... ---\n")
   covariates <- c(arm_var, linear_terms)
   all_vars <- c(time_var, status_var, strata_var, covariates)
   df <- pilot_data[stats::complete.cases(pilot_data[, all_vars]), ]
   n_pilot <- nrow(df)

   df$Y_rmst <- pmin(df[[time_var]], L)
   df$is_event <- df[[status_var]] == 1

   cens_formula <- stats::as.formula(paste0("survival::Surv(Y_rmst, is_event == 0) ~ ",
                                            paste(covariates, collapse = " + "),
                                            " + survival::strata(", strata_var, ")"))
   fit_cens <- survival::coxph(cens_formula, data = df, ties = "breslow")

   bh_cens <- survival::basehaz(fit_cens, centered = FALSE)
   df$H_cens <- 0
   unique_strata_from_bh <- unique(bh_cens$strata)
   for(st in unique(df[[strata_var]])){
      st_label <- paste0(strata_var, "=", st)
      is_stratum <- df[[strata_var]] == st
      if (st_label %in% unique_strata_from_bh) {
         is_bh_stratum <- bh_cens$strata == st_label
         if(sum(is_bh_stratum) > 0){
            H_st <- stats::stepfun(bh_cens$time[is_bh_stratum], c(0, bh_cens$hazard[is_bh_stratum]))(df$Y_rmst[is_stratum])
            df$H_cens[is_stratum] <- H_st
         }
      }
   }
   df$weights <- exp(df$H_cens * exp(stats::predict(fit_cens, newdata=df, type="lp", reference="zero")))
   df$weights[!df$is_event] <- 0
   finite_weights <- df$weights[is.finite(df$weights) & df$weights > 0]
   if (length(finite_weights) > 0) {
      weight_cap <- stats::quantile(finite_weights, probs = 0.99, na.rm = TRUE)
      df$weights[df$weights > weight_cap] <- weight_cap
   }
   df$weights[!is.finite(df$weights)] <- 0

   vars_to_center <- c("Y_rmst", covariates)
   stratum_means <- df %>%
      dplyr::group_by(.data[[strata_var]]) %>%
      dplyr::summarise(
         dplyr::across(
            dplyr::all_of(vars_to_center),
            ~ weighted.mean(.x, w = weights, na.rm = TRUE)
         ),
         .groups = 'drop'
      )
   names(stratum_means) <- c(strata_var, paste0(vars_to_center, "_mean"))

   df_centered <- df %>% dplyr::left_join(stratum_means, by = strata_var)
   for (cov in vars_to_center) {
      df_centered[[paste0(cov, "_tilde")]] <- df_centered[[cov]] - df_centered[[paste0(cov, "_mean")]]
   }

   Z_tilde <- as.matrix(df_centered[, paste0(covariates, "_tilde")])
   Y_tilde <- df_centered[["Y_rmst_tilde"]]
   W <- df_centered$weights

   A_hat_num <- crossprod(Z_tilde * sqrt(W))
   dimnames(A_hat_num) <- list(covariates, covariates)
   A_hat <- A_hat_num / n_pilot

   # CORRECTED: Add error handling for singular matrix
   A_hat_inv <- tryCatch({
      solve(A_hat)
   }, error = function(e) {
      stop("The covariate matrix (A_hat) is singular and cannot be inverted.\nThis may be caused by a lack of variation in the covariates among subjects with an event within one or more strata.\nPlease inspect the pilot data for issues like perfect separation.", call. = FALSE)
   })

   beta_hat <- (A_hat_inv / n_pilot) %*% (t(Z_tilde * W) %*% Y_tilde)
   rownames(beta_hat) <- covariates
   beta_effect <- beta_hat[arm_var, 1]

   mu0_hats <- stratum_means %>%
      dplyr::mutate(
         Z_matrix = as.matrix(dplyr::select(., dplyr::all_of(paste0(covariates, "_mean")))),
         mu0_hat = .data[["Y_rmst_mean"]] - Z_matrix %*% beta_hat
      ) %>%
      dplyr::select(dplyr::all_of(strata_var), mu0_hat)

   df_final <- df_centered %>% dplyr::left_join(mu0_hats, by = strata_var)
   Z_matrix <- as.matrix(df_final[, covariates])
   df_final$residuals <- df_final$Y_rmst - (df_final$mu0_hat + as.vector(Z_matrix %*% beta_hat))

   epsilon <- apply(Z_tilde, 2, function(z_col) z_col * W * df_final$residuals)
   B_hat <- crossprod(epsilon) / n_pilot
   dimnames(B_hat) <- list(covariates, covariates)

   V_hat_n <- A_hat_inv %*% B_hat %*% t(A_hat_inv)

   var_beta_pilot <- V_hat_n[arm_var, arm_var] / n_pilot
   var_beta_n1 <- var_beta_pilot * n_pilot
   se_beta_n1 <- sqrt(var_beta_n1)

   # --- 2. Iterative Search for Sample Size ---
   cat("--- Searching for Sample Size (Method: Additive Analytic) ---\n")
   current_n <- n_start
   search_path <- list()
   final_n <- NA_integer_
   z_alpha <- stats::qnorm(1 - alpha / 2)
   n_strata <- length(unique(df[[strata_var]]))

   while (current_n <= max_n_per_arm) {
      total_n <- current_n * n_strata
      se_final <- se_beta_n1 / sqrt(total_n)
      calculated_power <- stats::pnorm((abs(beta_effect) / se_final) - z_alpha)
      if (!is.finite(calculated_power)) calculated_power <- 0

      search_path[[as.character(current_n)]] <- calculated_power
      cat(paste0("  N = ", current_n, "/stratum, Calculated Power = ", round(calculated_power, 3), "\n"))

      if (calculated_power >= target_power) {
         final_n <- current_n
         break
      }
      current_n <- current_n + n_step
   }

   if (is.na(final_n)) {
      warning(paste("Target power", target_power, "not achieved by max N of", max_n_per_arm), call. = FALSE)
      final_n <- max_n_per_arm
   }

   # --- 3. Finalize and Return Results ---
   results_summary <- data.frame(Statistic = "Assumed RMST Difference (from pilot)", Value = beta_effect)
   results_df <- data.frame(Target_Power = target_power, Required_N_per_Stratum = final_n)
   search_path_df <- data.frame(N_per_Stratum = as.integer(names(search_path)), Power = unlist(search_path))

   p <- ggplot2::ggplot(na.omit(search_path_df), ggplot2::aes(x = N_per_Stratum, y = Power)) +
      ggplot2::geom_line(color = "#009E73", linewidth = 1) +
      ggplot2::geom_point(color = "#009E73", size = 3) +
      ggplot2::geom_hline(yintercept = target_power, linetype = "dashed", color = "red") +
      ggplot2::geom_vline(xintercept = final_n, linetype = "dotted", color = "blue") +
      ggplot2::labs(
         title = "Analytic Sample Size Search: Additive Stratified RMST Model",
         subtitle = "Power calculated from formula at each step.",
         x = "Sample Size Per Stratum", y = "Calculated Power"
      ) + ggplot2::theme_minimal()

   cat("\n--- Calculation Summary ---\n")
   print(knitr::kable(results_df, caption = "Required Sample Size"))

   return(list(results_data = results_df, results_plot = p, results_summary = results_summary))
}

