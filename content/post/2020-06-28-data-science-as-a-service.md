---
title: 'Online payments for data science apps (DSaaS) using R, Shiny, Firebase, Paddle and Google Cloud Functions'
author: Mark Edmondson
date: '2020-06-28'
slug: datascience-aas
tags:
  - R
  - firebase
  - google-auth
  - cloud-functions
  - python
banner: ../banners/piketty-capital.png
description: 'A bootstrap example on how to create a paid data science app (DSaaS)'
images: []
menu: ''
---

This post has been delayed due to the events of 2020 including a global pandemic and social justice demonstrations, if you are touched by those I wish you all the best.  For my family and I we have been very lucky and spent most of the last months tending our garden in the Copenhagen suburbs, but others have been a lot more directly affected.

One consequence of the pandemic may be that from now on more interaction will be online, which presents both opportunities and challenges.  I think it's important that any opportunities are democratised as much as possible, so I hope this post will help those with data science skills have an easier route to generate an income from those skills if they choose to. 

The demo tech stack chosen is one to keep online payments as simple yet as secure as possible, with low running costs taken care of via serverless infrastructure. 

The [demo app code is on GitHub available here](https://github.com/MarkEdmondson1234/Shiny-R-SaaS) and a working demo with that code is running on [shinyapps.io here.](https://mark.shinyapps.io/r-saas/)

## Money and open source software

The interaction between open-source and how it's paid for is interesting economics.  There are several open-source projects that are highly valuable and essential for modern living, yet created by people in their free time with no expectation of payment.  Indeed, from my own experience, the motivations to create these open source projects are more about craftsmanship, education and pride than any promise of monetary reward.

Yet if those projects are to go beyond hobby projects, at some point the open source contributor needs to be paid, and this seems to happen in a few ways:

1. The employer of the contributor pays enough that they can work in their free time
   - This risks burnout of the contributor 
2. The employer agrees to subsidise the open source project directly
   - The employer may then want rights over the open source project, potentially compromising it
3. The open source project serves as a CV for demonstrating the contributors skill
   - The project may then be abandoned once the contributer is busy with paid projects
4. The open source project generates income from direct sponsorship of its users
   - With [GitHub Sponsors](https://github.com/sponsors) this is now easier than ever, and may be the future of open source, although favours public facing projects over critical infrastructure
5. The open source project offers paid options on top of the free to use version, which supports the open-source work
   - This is the RStudio (PBC) model, with paid enterprise options supporting huge open source efforts

If we're lucky the contributor finds how to make one of the above work.  For example Hadley Wickham and Wes McKinney were employed by firms who wanted to support the open source work they were doing directly.  But what about those projects that rely on free time or user contributions?  Unfortunately, the most likely possibility is that they have to stop supporting the project - we can at best hope the person got a good job via the CV recognition route.

My ambition is that the demo payment template described in this post will help people into easier direct sponsorship or dedicated apps before they are abandoned. 

## GitHub Sponsors

GitHub Sponsors has also been a huge step in this area and there was [a recent report of a contributor with a $100k salary](https://calebporzio.com/i-just-hit-dollar-100000yr-on-github-sponsors-heres-how-i-did-it) which is fantastic. 

I am humbled by the people who have also [sponsored my efforts](https://github.com/sponsors/MarkEdmondson1234).  

![](/images/github-sponsors.png)

Thank you!

Any feedback is always a great motivation for me to carry on with my work (I used to fret I got no-one creating GitHub issues) and it never is taken for granted.  To have some who will actually take the time to send some money with that feedback is amazing and was another motivation to give back with this project.  It greatly reduces burnout to know that the work has some value to others.

## R as a production language

Another motivation for this template is to help sustain R programmers in particular.  Although the demo payment flow will work with any service (the Paddle javascript embeds in any HTML) I focused on making a front end for R using Shiny as there is a thirving ecosystem of [fantastic Shiny apps](https://shiny.rstudio.com/gallery/) that are currently offered for free, and I think it'll be cool if there are more that also generate income for their creators.  

![](/images/shiny-showcase.png)

A myth that R can't be used in production is possibly perpetrated as it has arisen via academia and so commercial applications haven't been a priority.  Nothing cements R as a production language more than if people are making a living from it. I certainly do in my day-to-day work at [IIH Nordic](https://iihnordic.com/), but anything to help others have the same is probably worth while. 

## The demo DSaaS (Data Science as a Service)

The [demo app code is on GitHub available here](https://github.com/MarkEdmondson1234/Shiny-R-SaaS) and a working demo with that code is running on [shinyapps.io here.](https://mark.shinyapps.io/r-saas/)

![](/images/subscriber-content.png)

It features:

* Firebase to handle authentication and store subscription user data
* Paddle to handle payments, taxes and fulfillment
* Cloud Functions to sync changes between Paddle and Firebase
* Shiny frontend with demo content for 'free', 'logged in but not subscribed' and 'subscriber' content

The detailed setup steps needed are in the [GitHub readme](https://github.com/MarkEdmondson1234/Shiny-R-SaaS), for this blogpost I'll take about what choices were made and why.

## Overall flow

I used [`library(DiagrammeR)`](https://rich-iannone.github.io/DiagrammeR/) to plan out what flows were needed (click image to make bigger):

![](/images/paddle_flow.png)

It does take some planning!

The key areas are how a user logs on and the app knows they are a paid subscriber, and what happens offline if say the credit card is declined - the app needs to know this state has been updated the next time a user logs on. 

### Firebase

Firebase is a development platform for building mobile and web apps that is a layer on top of the Google Cloud Platform.

Firebase has many tools to help make application development easier, but only two were needed for this project: Firebase AuthUI and Firestore, a noSQL database.

![](/images/firebase-login.png)

Firebase AuthUI has been implemented for Shiny apps via JohnCoene's [firebase package](https://github.com/JohnCoene/firebase).  

> This has a nice open source story of taking inspiration from each other, first started by [Andy Merlino showing a POC of Firebase](https://github.com/shinyonfire/sof-auth-example) on Shiny, myself putting in the Firebase Auth UI module which helped simplify the code and finished and polished by John to make a simple and powerful Shiny package to implement Firebase authentication.

Its easy and secure to setup, and since the authentication uses a centralised database running on Firebase it works across apps/website so a user who logs in with Shiny can also be recognised elsewhere, which you can use to make a suite of services, support or apps. 

In a similar manner, Firestore is a noSQL database that is used to carry the subscription data, linked to the Firebase userId.  

![](/images/firebase-database.png)

Being noSQL it is quick for reads and also lets you keep historic events such as when a user subscribed, cancelled or updated. Since its on the Google Cloud Platform I could use [`googleAuthR`](https://code.markedmondson.me/googleAuthR/) to authenticate and generated the R function to read it:

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

For a long time I was thinking of using Stripe for this template, but whilst Stripe has a great API and I'd [worked with it before](https://github.com/MarkEdmondson1234/stripeR), there was still some work to do to make reliable payment apps such as handling when a user's card gets declined (how would your app know to deny paid content?) and international taxes etc.

The pitch of [paddle.com](https://paddle.com/) was that it took care of all that for you, so you are closer to a working app.  They do charge more per transaction than Stripe, so if you are looking for the cheapest then you may want to stick with Stripe and implement the "Stripe stack", but I figured it was worth it for keeping the implementation simple.

Paddle has a simple JavaScript button to implement the payment popups - 

```js
<script src="https://cdn.paddle.com/paddle/paddle.js"></script>
<script type="text/javascript">
	Paddle.Setup({ vendor: 1234567 });
</script>

...
// a buy button
<a href="#!" class="paddle_button" data-product="12345">Buy Now!</a>
```

![](/images/paddle-paymentstep-2.png)

Paddle then uses webhooks to communicate with your server (in this case, Firestore) - so the next ingredient was how to create a webhook for communication between Paddle and Firestore.  You can then test this from the Paddle UI:

![](/images/paddle-webhook-test.png)

### Google Cloud Functions

For simple "glue" data flows my go-to is Google Cloud Functions, as you only need write the code and deploy without needing to worry about servers or scale.  Firebase has its own Cloud Function UI as well but that only supports node.js, so I opted to use the GCP console Cloud Functions in Python3.7 (Its the same service and infrastructure as Firebase.)

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

The `event` collection is per userId, and gives the complete history of their transactions.

If implementing your own, make sure to use the verification code that checks the webhook is from a trusted source. Paddle supplies public/private keys and [code to check them](https://developer.paddle.com/webhook-reference/verifying-webhooks), which is important for payment applications - you can see the [full function here](https://github.com/MarkEdmondson1234/Shiny-R-SaaS/blob/master/payment_app/fb_functions/main.py). 

As it works off webhooks this means that even when a user is not on the app important updates will still be enacted (such as monthly credit card payments or declines) and it moves a lot of work off your app for verifying/authorizing users.

Once the cloud function is deployed then your app needs to only query if a subscription exists for the FirebaseId a user has just logged in with, and check that that subscription is still live.

### Shiny app

Finally the actual demo app is via Shiny, which is much like any other Shiny app but with three additions:

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

Another useful feature of Paddle is in its response it gives you cancel and update links unique to that user, so you can use those entries to create a UI for a subscriber that permits them to control their subscription:

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
  
  # only displays for subscribers
  output$paid_content <- renderPlot({
    req(subscriber())

    plot(iris)

  })
```

Put together this is a view for a non-subscriber vs a subscriber:

![](/images/non-subscriber-content.png)

![](/images/subscriber-content.png)

Its not pretty yet but thats for you to do :)

## Summary

I hope the above enables wonderful in-depth DSaaS that sustain both the contributors and the data science ecosystem in general.  Getting past all the boilerplate has certainly stopped me from creating apps in the past (I have a few failed projects in the closet), so I hope now this template exists it will be easier to launch.  

All we need are some good ideas on what people would be happy to pay for, and that is a whole other blog post I guess of which I have not yet much experience. 

You can substitute Shiny for a Python Flask app, HTML page or even an Excel sheet you send people.  Its really just a matter of what you think would be suitable.  There is also the matter of marketing, adding value with your app, customer service etc. that are all still to be tackled, but at least you can start moving down that track rather than the boring financial bits ;)  

If you do make anything derived from it, please do let me know as I'd love to hear what you are doing, and if you can see ways to improve the template feel free to raise an issue on the [project's GitHub issues](https://github.com/MarkEdmondson1234/Shiny-R-SaaS/issues). 
