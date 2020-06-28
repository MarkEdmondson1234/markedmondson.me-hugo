---
title: 'Accepting online payments for your data science apps - why, how and a demo using R Shiny, Firebase, Paddle and Google Cloud Functions'
author: Mark Edmondson
date: '2020-06-28'
slug: datascience-aas
tags:
  - R
  - firebase
  - google-auth
  - cloud-functions
  - python
banner: ../banners/gcp-pyramid.png
description: 'A bootstrap example on how to create a paid data science app (DSaaS)'
images: []
menu: ''
---

This post has been delayed due to the events of 2020 including a global pandemic and social justice demonstrations, if you are touched by those I wish you all the best.  For my family and I we have been very lucky and spent most of the last months tending our garden in the Copenhagen suburbs, but others have been a lot more directly affected.

One consequence of the pandemic may be that from now on more interaction will be online, which presents both opportunities and challenges.  I think it's important that any opportunities are democratised as much as possible, so I hope this post will help those with data science skills have an easier route to generate an income from those skills if they want. 

The demo tech stack chosen is one to keep online payments as simple yet as secure as possible, with low running costs taken care of via serverless infrastructure. 

## Money and open source software

The interaction between open-source and how it's paid for is interesting economics.  There are several open-source projects that are highly valuable and essential for modern living, yet created by people in their free time with no expectation of payment.  Indeed, from my own experience, the motivations to create these open source projects are more about craftsmanship, education and pride than any promise of monetary reward.

Yet if those projects are to go beyond hobby projects, at some point the open source contributor needs to be paid, and this seems to happen in a few ways:

* The employer of the contributor pays enough that they can work in their free time
   - This risks burnout of the contributor 
* The employer agrees to subsidise the open source project directly
   - The employer may then want rights over the open source project, potentially compromising it
* The open source project serves as a CV for demonstrating the contributors skill
   - The project may then stop being worked on if the contributer is busy with other projects
* The open source project generates income from direct sponsorship of its users
   - With GitHub sponsors this is now easier than ever, and may be the future of open source, although favours public facing projects and not critical infrastructure
* The open source project offers paid options on top of the free to use version, which supports the open-source work
   - This is the RStudio (PBC) model, with paid enterprise options supporting huge open source efforts

If we're lucky the contributor finds how to make one of the above work.  For example Hadley Wickham and Wes McKinney were employed by firms who wanted to support the open source work they were doing directly.  But what about those projects that rely on free time or user contributions?  Unfortunately, the most likely possibility is that they have to stop supporting the project, hopefully because the project got that person a good job via the CV recognition route.

I hope the demo payment template will help move people into easier direct sponsorship or dedicated apps.  

## GitHub Sponsors

GitHub Sponsors has also been a huge step in this area and there was [a recent report of a contributor with a $100k salary](https://calebporzio.com/i-just-hit-dollar-100000yr-on-github-sponsors-heres-how-i-did-it) which is fantastic. 

I am humbled by the people who have also [sponsored my efforts](https://github.com/sponsors/MarkEdmondson1234).  Any feedback is always a great motivation for me to carry on with my work (I used to fret I got no-one creating GitHub issues) and it never is taken for granted.  To have some who will actually take the time to send some money with that feedback is amazing and was another motivation to give back with this project.  It greatly reduces burnout to know that the work has some value to others.

## R as a production language

Another motivation for this template is to help sustain R programmers in particular.  Although the demo payment flow will work with any service (the Paddle javascript embeds in any HTML) I focused on making a front end for R using Shiny as there is a thirving ecosystem of fantastic Shiny apps that are currently offered for free, and I think it'll be cool if there are more that also generate income for their creators.  

A myth that R can't be used in production is possibly perpetrated as it has arisen via academia and so commercial applications haven't been a priority.  Nothing cements R as a production language more than if people are making a living from it. I certainly do in my day-to-day work at IIH Nordic, but anything to help others have the same is probably worth while. 

## The demo DSaaS (Data Science as a Service)

The [demo app code is on GitHub available here](https://github.com/MarkEdmondson1234/Shiny-R-SaaS) and a working demo with that code is running on [shinyapps.io here.](https://mark.shinyapps.io/r-saas/)

It features:

* Firebase to handle authentication and store subscription user data
* Paddle to handle payments, taxes and fulfillment
* Cloud Functions to synch changes between Paddle and Firebase
* Shiny frontend with demo free, login but not subscribed yet and subscribed content

The detailed setup steps needed are in the GitHub readme, for this blogpost I'll take about what choices were made and why.

### Firebase

Firebase is a service for building apps and web apps that is a layer on top of the Google Cloud Platform that I specialise in.

Firebase has many tools to help make application development easier, but only two were needed for this project: Firebase AuthUI and Firestore, a noSQL database.

Firebase AuthUI has been implemented for Shiny apps via JohnCoene's [firebase package](https://github.com/JohnCoene/firebase) which has been a nice open source story of taking inspiration from each other, first started by [Andy Merlino showing a POC of Firebase](https://github.com/shinyonfire/sof-auth-example) on Shiny, myself putting in the Firebase Auth UI module which helped simplify the code and finished and polished by John to make a simple and powerful Shiny package to implement Firebase authentication.

Its easy and secure to setup, and since the authentication uses a centralised database running on Firebase it works across apps/website so a user who logs in with Shiny can also be recognised elsewhere, which you can use to make a suite of services, support or apps. 

In a similar manner, Firestore is a noSQL database that is used to carry the subscription data, linked to the Firebase userId.  Being noSQL it is quick for reads and also lets you keep historic events such as when a user subscribed, cancelled or updated. Since its on the Google Cloud Platform I could use `googleAuthR` to authenticate and generated the R function to read it:

```r
library(googleAuthR)

gar_auth_service("firebase-reader-auth-key.json",
                 scope = "https://www.googleapis.com/auth/datastore")

#' Gets a Firebase data entry.  Will return NULL if it can not
fb_document_get <- function(document_path,
                            database_id = "(default)",
                            project_id = Sys.getenv("FIREBASE_PROJECT")){

  the_url <- sprintf("https://firestore.googleapis.com/v1/projects/%s/databases/%s/documents/%s",
                     project_id, database_id, document_path)

  f <- gar_api_generator(the_url,
                         "GET",
                         data_parse_function = function(x) x)

  f()
}
```

### Paddle

For a long time I was thinking of using Stripe for this app, but whilst Stripe has a great API and I'd worked with it before, there was still some work to do to make reliable payment apps such as handling when a user's card gets declined (how would your app know to deny paid content?) and international taxes etc.

The pitch of [paddle.com](https://paddle.com/) was that it took care of all that for you, so you are closer to a working app.  They do charge more per transaction than Stripe, so if you are looking for the cheapest then you may want to stick with Stripe and implement the "Stripe stack", but I figured it was well worth it for keeping the payments simple.

Paddle has a simple JavaScript button to implement the payment popups and then uses webhooks to communicate with your server (in this case, Firestore) - so the next ingredient was how to create a webhook for communication between Paddle and Firestore.

### Cloud Functions

For the simple "glue" data flows my go-to is Google Cloud Functions, as you only need write the code and deploy without needing to worry about servers or scale.  Firebase has its own Cloud Function UI as well but that only supports node.js, so I opted to use the GCP console Cloud Fucntions in Python3.7.  Its the same service and infrastructure as Firebase.

Paddle had lots of Python examples already on the website on how to verify and deal with the data in their webhook payload so a lot of it was just copy-paste from there into the Cloud Function UI.  There is some more setup info in the [Cloud Function readme](https://github.com/MarkEdmondson1234/Shiny-R-SaaS/tree/master/payment_app) - the only extra bit I needed to add was how to take the webhook payload and write it to Firestore - this was all handled by this snippet of code:

```python
import logging
from google.cloud import firestore

def update_firebase(data, collection, doc_id):
    logging.info('fb update - collection {} doc_id {}'.format(collection, doc_id))

    db = firestore.Client()
    doc_ref = db.collection(collection).document(doc_id)
    doc_ref.set(data)

    # add the event
    event_ref = db.collection(collection).document(doc_id).collection('event').document(data['alert_id'])
    event_ref.set(data)   
```

Before writing to Firebase though Paddle gives you code to verify that the data is from a trusted source which it achieves via public/private keys which is important for payment applications - you can see the [full function here](https://github.com/MarkEdmondson1234/Shiny-R-SaaS/blob/master/payment_app/fb_functions/main.py). 

As it works off webhooks this means that even when a user is not on the app important updates will still be enacted (such as monthly credit card payments or declines) and it moves a lot of work off your app for verifying/authorizing users.

Once the function is deployed then your app needs to only query if a subscription exisits for the FirebaseId a user has just logged in with, and check that that subscription is still live.

### Shiny app

Finally the actual data app can live in a Shiny app, much like any other Shiny app but with three additions:

* A login screen presenting Firebase Auth
* A check that a user is logged in before showing free content
* A check that a user is a subscriber before showing paid content

The first two are provided by John's firebase library - see [the website on setting it up](https://firebase.john-coene.com/articles/ui.html) :

```r
library(shiny)
library(firebase)

ui <- fluidPage(
  useFirebase(), # import dependencies
  useFirebaseUI(),
  reqSignin(h4("VIP plot below")), # hide from UI
  plotOutput("plot")
)

server <- function(input, output){
  f <- FirebaseUI$
    new()$ # instantiate
    set_providers( # define providers
      email = TRUE, 
      google = TRUE
    )$
    launch() # launch

  output$plot <- renderPlot({
    f$req_sign_in() # require sign in
    plot(cars)
  })
}

shinyApp(ui, server)
```

The check that a user is a subscriber involves taking the FirebaseId and seeing if it has a live entry in the subscriptions Firestore.

Another useful feature of Paddle is in its response it gives you cancel and update links unique to that user, so you can use those entries to creates a UI for a subscriber:

```r
  # NULL if no subscription
  subscriber <- reactive({
    req(firebase_user())

    # fb_document_get() is defined in global.R 
    o <- fb_document_get(paste0("subscriptions/", firebase_user()$uid))

    if(!is.null(o) && o$fields$status$stringValue == "deleted"){
      # has subscription entry but it is cancelled
      return(NULL)
    }

    o

  })

  subscriber_details <- reactive({
    req(subscriber())
    ss <- subscriber()

    tagList(
      div(class="card",
        h3("Subscription details"),
        p("Status:", ss$fields$status$stringValue),
        p(class="email", ss$fields$email$stringValue),
        p("Last update: ", ss$fields$event_time$stringValue),
        p("Next bill date:", ss$fields$next_bill_date$stringValue),
        p(a(href=ss$fields$update_url$stringValue,
          "Update your subscription",
                             icon = icon("credit-card"),
                             class = "btn-info")),
        " ",
        p(a(href=ss$fields$cancel_url$stringValue,
          "Cancel your subscription",
                      icon = icon("window-close"),
                      class = "btn-danger"))
        )
      )

  })
```

## Summary

I hope the above enables uses to create wonderful in-depth DSaaS that helps sustain both the contributors and the ecosystem in general.  Getting past all the boilerplate certainly stopped me from creating apps before (I have a few failed projects in the closet), so I hope now I can use this template to create my own if needed.  All we need are some good ideas on what people would be happy to pay for, and that is a whole other blog post I guess of which I have yet little experience. 

You can substitute Shiny for a Python Flask app, HTML page or even an Excel sheet you send people.  Its really just a matter of what you think would be suitable.  There is also the matter of marketing, adding value with your app, customer service etc. that are all still to be tackled, but at least you can start moving down that track rather than the boring finacial bits ;)  If you make anything with it, please do let me know as I'd love to hear what you are doing. 









