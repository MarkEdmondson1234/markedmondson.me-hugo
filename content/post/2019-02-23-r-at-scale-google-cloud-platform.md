---
title: R at scale on the Google Cloud Platform
author: Mark Edmondson
date: '2019-02-23'
slug: r-at-scale-on-google-cloud-platform
tags:
  - docker
  - R
  - google-compute-engine
banner: ../banners/r-at-scale.png
description: 'Current thinking on what I consider the optimal way to work with R on Google Cloud Platform'
images: []
menu: ''
---

This post covers my current thinking on what I consider the optimal way to work with R on the Google Cloud Platform (GCP).  It seems this has developed into my niche, and I get questions about it so would like to be able to point to a URL.

Both R and the GCP rapidly evolve, so this will have to be updated I guess at some point in the future, but even as things stand now you can do some wonderful things with R, and can multiply those out to potentially billions of users with GCP.  The only limit is ambition.

The common scenarios I want to cover are:

* Scaling a standalone R script
* Scaling Shiny apps  
* R APIs
* Machine learning with R 

## It almost always starts with Docker

Docker is the main mechanism to achieve scale on GCP.  

It encapsulates code into a unit of computation that can be built on top of, one which doesn't care which language or system that code needs to run.  

This means that a lot of the techniques described are not specific to R - you could have components running python, Java, Rust, Node, whatever is easiest for you.  I do think that Docker's strengths seems to cover R's weaknesses particularly well, but having Docker skills is going to be useful whatever you are doing, and is a good investment in the future.

There is growing support for Docker in R, of which I'll mention:

* [The Rocker Project](https://www.rocker-project.org/) is where it all flows from, providing useful R Docker images
* [containerit](http://o2r.info/containerit/index.html) is helpful to quickly generate a Dockerfile from an R script or project
* [steveadore](https://richfitz.github.io/stevedore/) is a Docker client written in R

Within GCP containers are fundamental and once you have your Docker image, will be able to use many of its services both now and in the future, as well as on other cloud providers.  The tools I use day to day with my Docker workflows are:

* [Build Triggers](https://cloud.google.com/cloud-build/docs/running-builds/automate-builds) - I never build Docker on my machine, I always commit the Dockerfiles to GitHub and then this service builds them for me. 
* [Container registry](https://cloud.google.com/container-registry/) - Once built images are available from here.  They are by default private, and over time I've built a library of useful images.  Some of these are available [publically at this repo](https://console.cloud.google.com/cloud-build/triggers?project=gcer-public&organizationId=1054872852559) (you do need to login though)

The above are used within [googleComputeEngineR's templates](https://cloudyr.github.io/googleComputeEngineR/reference/gce_vm_template.html), so as RStudio, Shiny and R APIs can be launched quickly. 

### 1. Scaling an R script

The first scenario is where you have a script that does something cool, but now you need it to say run on a schedule, run against more data than you can throw at it locally, or just don't have the resources.  In that case you can choose to scale either horizontally or vertically.

#### 1A - Getting a bigger boat

Vertical scaling is where you just throw more power at the problem.  As R is RAM based, then often the easiest solution is to just run the script on a machine with massive RAM.  

*Pros*

 - probably run the same code with no changes needed
 - easy to setup
 
*Cons*

 - expensive
 - may be better to have data in database

And it can be massive.  Google Compute Engine offers instances with up to 3.75TB of RAM which can probably eat most jobs. To do so, change the machine type to say `n1-ultramem-160` that gives you 160 CPU cores as well.  (The [ultra-mem machine type](https://cloud.google.com/compute/docs/machine-types#megamem))

Launching this with googleComputeEngineR:

```r
library(googleComputeEngineR)

# this will cost a lot
bigmem <- gce_vm("big-mem", template = "rstudio", predefined_type = "n1-ultramem-160")
```

This would however cost you $423 a day, so be ready before you launch such a beast.

#### Data size

However, it is rare that data is in a format that would directly benefit from this much RAM.  

Just reading the data will take time at this volumes, and should not be done via CSV files.

Better alternatives include [Apache arrow](https://github.com/apache/arrow/tree/master/r), [`library(feather)`](https://blog.rstudio.com/2016/03/29/feather/) or [`data.table()`](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-intro.html).  

But if your data is that size, then its probably better that it is accessed from a database, and for most analytics tasks like that I reach for BigQuery, which then follows that perhaps you don't need so much RAM if your code is batching operations on the data. For that you can use [`bigrquery`](https://bigrquery.r-dbi.org/) or [`bigQueryR`](http://code.markedmondson.me/bigQueryR/).



#### Horizontal scaling

This is actually the more common path for me, and its here where Docker starts to come into play.  The idea here is to split up your task into bite sized pieces, run your script on those bits then merge them all back together again, or a split-map-combine workflow.  Not all data problems can be tackled this way, but I would say most can be.

What appeals most to me here is that each time you build the blocks for a job, you may not have to start from scratch - for instance I often reuse images that say connect to BigQuery, and swap the script over. 

To achieve this has become a lot easier in R with the future() package, which standardises multicore processing in R, and enables one to take your code and work it on many cores or instances in the cloud.  Again, you may find this easier to do on one big VM with lots of cores, or many small VMs.  The code is similar in both cases, but the setup is not, and make sure ot include code to tear down the instances again afterwards. 

Pros:
- Docker image created that is available for other workflows
- future interface lets same code work with different scaling strategies like multisession, multicore or multi-instance.

Cons:
- probably have to change your code so it can be done via split-map-combine
- have to write meta code to handle the interface of data and code
- Not applicable to some problems that need to calculate on all data at once.

#### Horizontal Kubernetes

Another natural next option here is now you are using clusters of machines and Docker is that Kubernetes comes into play.  This can't be done using future() so is a bit more difficult to setup, but what Kubernetes offers is the auto-scaling and preemptive image management, which will be much cheaper in the long run if you need to do this kind of operation many times.

As the pods of Kubernetes are usually stateless (I don't know how to do a stateful cluster) then you need to make sure the data bits that each pod operates on is able to work completely separately, and also coordinate which bits have been worked on and which should be used for future. 

Pros
- takes advantage of Kubernetes features such as auto-scaling, task queues etc.
- potentially cheaper
Cons
- need to create stateless, idempotent workflows
- need to make some kind of message broker that decides which bits of data to work on for each pod. 

## Scaling Shiny apps

Here we really have two options, one for low traffic apps and the other for scaling to the world. 

### Dockerise your Shiny app

The first step is to copy your Shiny app folder into a Docker container with all the R libraries you need installed.  From there you are ready to take advantage of almost any cloud providers services. However, the biggest stumbling block I have found is that Shiny requires websocket support, which for some services are not available.  Check your solution first to see if it can deal with websockets before deployment. For instance, App Engine Flexible or Cloud Functions would be a better serverless solutions if the above was supported. 

### Kubernetes

Its mainly due to the need of websockets that I recommend going straight to Kubernetes once you have need for more than a couple of Shiny apps.  Kubernetes will take care of deploying the right number of pods to scale your traffic, and starts to make savings once you are past 3 VMs.  However, you may already have a kubernetes cluster deployed for other things, in which case you can hitch onto an existing cluster. 

Pros
- Scale to billions
- Keeps costs low
Cons
- Minimum useage level required to be better than just deploying on a single VM.

## R APIs

R currently has two popular ways to make an API out of R code, which once are in a Docker container deploy almost exactly the same.  OpenCPU requires you to make a package out of your code, so takes a little more R skill level, whereas plumber is very easy to get up and running.  Pick your favourite. 

Once you have a Docker container that responds with a HTTP request with your desired output, I again suggest Kubernetes as the best place to deploy this for the same reasons as the Shiny app.  In most cases, autoscaling is the killer feature so you aren't losing requests in high peaks or keeping around spare capacity when you are at traffic lows.

In addition, Cloud endpoints deploy onto the ip address of the kubernetes cluster, and provide tools to make the API manageable.  This tips towards using plumber as it provides the OpenAPI/swagger specification you need to configure it. 

I tip towards using Kubernetes rather than App Engine flexible from a cost perspective as App Engine flexible doesn't scale to 0 and you can use an existing Kubernetes cluster (Such as say for your Shiny apps)

## Machine learning with R

If using xgboost or tensorflow/keras and are using production models, then its almost always going to be better to use the cloudml() package for its serverless training and serving of your models.  However during development you may want your own GPU enabled VM which has just been developed in googleComputeEngineR



