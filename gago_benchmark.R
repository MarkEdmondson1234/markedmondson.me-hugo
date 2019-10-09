library(googleAnalyticsR)
library(microbenchmark)

Sys.setenv(GAGO_AUTH="/Users/mark/dev/auth/mark-edmondson-gde-auth.json")
googleAuthR::gar_auth_service(Sys.getenv("GAGO_AUTH"))

test_id <- 106249469	

slow_api <- function(){
  google_analytics(test_id, 
                   date_range = c("2018-01-01","2019-10-01"),
                   metrics = "sessions", 
                   dimensions = c("date","hour","campaign","landingPagePath"),
                   slow_fetch = TRUE,
                   max = -1)
} 

quicker_r <- function(){
  google_analytics(test_id, 
                   date_range = c("2018-01-01","2019-10-01"),
                   metrics = "sessions", 
                   dimensions = c("date","hour","campaign","landingPagePath"),
                   slow_fetch = FALSE,
                   max = -1)
}

gago_call <- function(){
  system("/Users/mark/dev/go/bin/gagocli reports -a /Users/mark/dev/auth/mark-edmondson-gde-auth.json -dims 'ga:date,ga:hour,ga:campaign,ga:landingPagePath' -end 2019-10-01 -max -1 -mets 'ga:sessions' -start 2018-01-01 -view 106249469 -o gago.csv")
  read.csv("gago.csv", stringsAsFactors = FALSE)
}

check_equal_rows <- function(values){
  all(sapply(values[-1], function(x) identical(values[[1]], x)))
}

mbm <- microbenchmark(
  slow = slow_api(),
  quick_r = quicker_r(),
  gago_call = gago_call(),
  times = 1
)

