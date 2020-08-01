---
title: 'Shiny on Google Cloud Run - Scale-to-Zero R Web Apps'
author: Mark Edmondson
date: '2020-08-01'
slug: shiny-cloudrun
tags:
  - R
  - docker
  - cloud-run
banner: ../banners/shiny-clouds.jpg
description: 'How to create scale-to-zero Shiny apps on Google Cloud Run: pitfalls, how and why'
images: []
menu: ''
---

There are some references on how to deploy Shiny apps to Cloud Run around the web and in various bits of my package documentation, but its a cool service so I thought it worth pulling out and having a blog post to refer to.

## Why Shiny on Cloud Run?

As mentioned in my [R at scale on Google Cloud Platform post](https://code.markedmondson.me/r-at-scale-on-google-cloud-platform/), Cloud Run is a container-as-a-service which lets you deploy Docker containers to the web without needing to worry about the infrastructure.  One of its most attractive features is the scaling, as you pay zero when your app has no visits, but as demand increases it can flexibly serve up your app to billions of users. 

Its like Google Cloud Functions or AWS Lambda functions, but unlike those Cloud Run works with any language since its using a Docker container that can carry any language that supports HTTP. Cloud Functions only works with the supported languages, such as Python.

I favour Cloud Run over [Kubernetes clusters](https://code.markedmondson.me/r-on-kubernetes-serverless-shiny-r-apis-and-scheduled-scripts/), since its simpler to deploy and maintain apps, and you don't need to pay at least $100 a month for a Kubernetes cluster.

For [R APIs such as plumber](https://www.rplumber.io/), Cloud Run is my recommended solution, since it can scale so well and the cost is good.  However, for Shiny I have to date still used Kubernetes as Cloud Run had some limitations which in my experiments meant Shiny did not function.  This blog post is about how and why to work around those limitations.

## Why Not Shiny on Cloud Run

The limitations that affect Shiny are around support for [websockets](https://rstudio.github.io/websocket/articles/overview.html) and the fact that Shiny is a stateful service, whereas Cloud Run is meant for stateless services.  

This means that for Cloud Run each HTTP request should not depend on previous HTTP requests, or is stateless. This is the case for an API, but Shiny is inherently a session based system: a user's past actions affect the current Shiny state. If a subsequent request to Shiny is directed to a different Shiny app than the one the user is in then we have problems.

As [RStudio's `jcheng5` put it](https://github.com/rstudio/shiny/issues/2455#issuecomment-497883381):

> Wait, is GCR akin to Amazon's Lambda? If so, I imagine this won't be a good fit for Shiny, no matter what software you put in the middle. These services are designed for stateless HTTP servers, and Shiny is inherently stateful. I bet you'd end up with errors under load as requests that can only be served out of container A (where its session lives in memory) end up being routed to container B instead.

As a newly launched service, for a long while Cloud Run did not support websockets.  That support is now enabled in some limited fashion, and so with a little configuration you can have a Shiny app running.

Thanks to `randy3k` the limitations above where navigated in the following ways:

* Limit the number of instances to 1 - this means there is only one instance to route requests too
* Disable some websocket protocols to only leave those that work with Cloud Run - namely `disable_protocols websocket xdr-streaming xhr-streaming iframe-eventsource iframe-htmlfile xdr-polling iframe-xhr-polling;`

[See `randy3k`'s GitHub repo with a sample app solving the issues here](https://github.com/randy3k/shiny-cloudrun-demo).

The above means that your Shiny app is limited though: the number of concurrent requests you can have to one container in Cloud Run is 80 connections.  This means you lose the "scale-to-a-billion"" feature as on concurrent request 81 no container will be available to serve it, and it also means the app won't autoscale as the normal Cloud Run would.  For normal applications, Cloud Run allows 1000 containers with up to 80 requests each e.g. 80,000 concurrent requests.  

Having only one container also means that you need to worry about the footprint of your Shiny app.  Whereas if it autoscaled high CPU/RAM load would trigger another container, for one container CLoud Run has a limit of 80 but the real limit will be how much traffic your Shiny app can handle, which depends on how much CPU/RAM your Shiny app uses.  This is much like a traditional Shiny server running on say [`googleComputeEngineR`](https://cloudyr.github.io/googleComputeEngineR/).

However, the above still leaves some use cases where Shiny is useful:

* If your peak traffic is below 80 concurrent users e.g. 80 people browsing at the same time
* And your app load on CPU/RAM is small enough to support your expected amount of concurrent users.

For APIs the above limitations would be a problem as they can be queried thousands of times an hour, but since Shiny is usually a dashboard option for a select group of users, I think this leaves a lot of room for Shiny on Cloud Run being viable, plus you also get the killer feature of scaling to 0 in the downtime between user sessions, which gives it the advantage over other solutions such as running your own Shiny server.

Another big plus for me is that as its running on Google infrastructure, this means OAuth2 workflows are automatically on the accepted list of domains - this means setup for OAuth2 buttons using say [`googleAuthR::googleAuth_js`](https://code.markedmondson.me/googleAuthR/reference/googleAuth_js.html) is simpler and doesn't involve validating a domain.

If your Shiny app expects big peaks of traffic however, or is a big heavy app in terms of resources, then you are probably best looking at other options.  For me, this is keeping the existing [Shiny deployments running on Google Kubernetes Engine](https://code.markedmondson.me/r-on-kubernetes-serverless-shiny-r-apis-and-scheduled-scripts/).

## How to deploy Shiny on Cloud Run

Cloud Run is such a useful service it is included in my newest package, `googleCloudRunner` as a [build template](https://code.markedmondson.me/googleCloudRunner/reference/cr_buildstep_run.html) and [deployment option](https://code.markedmondson.me/googleCloudRunner/reference/cr_deploy_run.html).  To accomodate the limitations above, the latest version (on GitHub now but on CRAN soon as v0.3) includes parameters to enable Shiny on Cloud Run in CI/CD workflows e.g. if you supply your app and Dockerfile, it will build the Cloud Run container with your Shiny app embedded and deploy it for you.  

You can set this up so it will trigger on each commit to git (say GitHub) so you can quickly make code changes and see it deployed on a URL.

### Hello World

The first example uses [`randy3k`'s example](https://github.com/randy3k/shiny-cloudrun-demo).  You will need to clone the repo so that you have a local version of the Dockerfile and `app.R` containing the Shiny app.

Once you have the repo in say folder `shiny-app/` then you can build its Dockerfile and then deploy the app with one function:

```r
# set up via googleCloudRunner::cr_setup() first if you haven't done so
library(googleCloudRunner)

# deploy the app version from this folder
cr_deploy_run("shiny-app/",
              remote = "shiny-cloudrun",
              max_instances = 1, # required for shiny
              concurrency = 80)
```

### Authenticated Shiny App

This is the example deployed to `https://shiny-cloudrun-sc-ewjogewawq-ew.a.run.app/`

This demonstrates deploying an app with a Google login, in this case for Search Console.

The difference here is to also add a `client.json` file to help with the authentication app, and setting up the Cloud Run domain as a verified OAuth2 source.  This is the example in the [googleCloudRunner Cloud Run documentation](https://code.markedmondson.me/googleCloudRunner/articles/cloudrun.html#shiny-app-on-cloud-run-with-googleauthr-authentication-1)

Folder:
```
|
|- app.R
|- Dockerfile
|- client.json
|- shiny-customized.config
```

#### app.R

```r
library(shiny)
library(searchConsoleR)
library(googleAuthR)

gar_set_client(web_json = "client.json",
               scopes = "https://www.googleapis.com/auth/webmasters")

ui <- fluidPage(
  googleAuth_jsUI('auth', login_text = 'Login to Google'),
  tableOutput("sc_accounts")
)

server <- function(input, output, session) {
  auth <- callModule(googleAuth_js, "auth")

  sc_accounts <- reactive({
    req(auth())

    with_shiny(
      list_websites,
      shiny_access_token = auth()
    )

  })

  output$sc_accounts <- renderTable({
    sc_accounts()
  })


}

shinyApp(ui = ui, server = server)
```

#### Dockerfile

```
FROM rocker/shiny

# install R package dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev libssl-dev \
    ## clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/ \
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds

## Install packages from CRAN
RUN install2.r --error \
    -r 'http://cran.rstudio.com' \
    googleAuthR searchConsoleR

COPY shiny-customized.config /etc/shiny-server/shiny-server.conf
COPY client.json /srv/shiny-server/client.json
COPY app.R /srv/shiny-server/app.R

EXPOSE 8080

USER shiny

# avoid s6 initialization
# see https://github.com/rocker-org/shiny/issues/79
CMD ["/usr/bin/shiny-server"]
```

#### client.id and GCP setup

The client.json was a web client json from my project:

```json
{"web":{"client_id":"10XXX","project_id":"XXXX","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://accounts.google.com/o/oauth2/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_secret":"XXXXX","redirect_uris":["http://localhost"],"javascript_origins":["https://www.example.com","http://localhost:1221"]}}
```

You need to add the domain of where the Cloud Run is running in the JavaScript origins within the GCP console, that you get after deploying the app. (GCP console > APIs & Services > Credentials > Click on the Web Client ID you are using > Add URL to Authorised JavaScript origins).

![](/images/javascript-origins.png)

In the example case this is `https://shiny-cloudrun-sc-ewjogewawq-ew.a.run.app/`

*It did take a while for this to propagate, so if your login doesn't work after this step try again in a few hours*

#### shiny-customized.config

This is the configuration file for Shiny that will overwrite the default one - its main purpose is turning off the websocket functionality that is not supported on Cloud Run

```
disable_protocols websocket xdr-streaming xhr-streaming iframe-eventsource iframe-htmlfile xdr-polling iframe-xhr-polling;

run_as shiny;

server {
  listen 8080;

  location / {
    site_dir /srv/shiny-server;

    log_dir /var/log/shiny-server;

    directory_index off;
  }
}
```

#### Deploying

You can then deploy similar to the example above, which will build the Dockerfile and then deploy it to Cloud Run.

```r
# deploy the app version from this folder
cr_deploy_run("shiny_cloudrun/app/",
              remote = "shiny-cloudrun-sc",
              max_instances = 1, # required for shiny
              concurrency = 80)
```

## Summary

Deploying Shiny to Cloud Run opens up a lot more experimentation with Shiny apps for me since they can be deployed for zero cost, and also gets around the authentication OAuth2 issues I was having on `shinyapps.io` since the authorization rules tightened.

If a Shiny app gets too popular for Cloud Run, then it may need migrating to another service but thats a nice problem to have and since its in a Docker container already thats a smooth switch (and there is another [googleCloudRunner example for deploying Shiny to Kuberentes](https://code.markedmondson.me/googleCloudRunner/articles/usecases.html#deploy-a-shiny-app-to-google-kubernetes-engine-1))

Coupled with the workflow to [make paid Shiny apps](https://code.markedmondson.me/datascience-aas/) it paves the path to narrow focus but useful paid data science apps.

Many thanks to all the members of the R community who helped solve this problem - `rankdy3k` as mentioned above but also `maxheld83`, `jchen5` and `jdwrink` who first raised the [issue on the shiny GitHub](https://github.com/rstudio/shiny/issues/2455).

When researching this post I also found this [guide on how to publish Shiny on Google Cloud Run by Vabhav Ararwal](https://medium.com/engineered-publicis-sapient/google-cloud-run-best-bet-to-host-shiny-application-3aa1e18770a9) that uses the Web UI a bit more. 


