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

One consequence of the pandemic may be that from now on more interaction will be online, which presents both opportunities and challenges.  I think its important that any opportunities are democratised as much as possible, so I hope this post will help those with data science skills have an easier route to generate an income from those skills if they want. 

The tech stack chosen is one to keep online payments as simple yet secure as possible, with low running costs taken care of via serverless infrastructure. 

## Money and open source software

The interaction between open-source and how its charged for is interesting economics.  There are several open-source projects that are highly valuable and essentially for modern living, yet created by people in their free time with no expectation of payment.  Indeed from my own experience the motivations to create these open source projects is more about craftsmanship, education and pride than any promise of monetary reward.

Yet if those projects are to go beyond hobby projects, at some point the open source contributor needs to be paid, and this seems to happen in a few ways:

* The employer of the contributor pays enough that they can work in their free time
   - This risks burnout of the contributor 
* The employer agrees to subsidise the open source project directly
   - The employer may then want rights over the open source project, potentially compromising it
* The open source project serves as a CV for demonstrating the contributors skill, and they get side-projects from it
   - The project may then stop being worked on if the contributer is busy with the other projects
* The open source project generates income from direct sponsorship of its users
   - With GitHub sponsors this is now easier than ever, and may be the future of open source
* The open source project offers paid options on top of the free to use version, that supports the open-source work
   - This is the RStudio (PBC) model, with paid enterprise options supporting huge open source efforts




