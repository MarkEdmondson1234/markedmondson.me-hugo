---
title: 'Google Tag Manager Server Side on Cloud Run - Pros and Cons'
author: Mark Edmondson
date: '2020-08-21'
slug: gtm-serverside-cloudrun
tags:
  - google-tag-manager
  - docker
  - cloud-run
banner: ../banners/princess-gtm.png
description: 'Is Cloud Run viable for running Google Tag Manager server-side?'
images: []
menu: ''
---

One of the most exciting developments in 2020 for me is the launch of [Google Tag Manager Server Side](https://developers.google.com/tag-manager/serverside), which lies at the intersection of cloud and digital analytics that I've gravitated towards in recent years.

There are many good resources out there on GTM Serverside, [Simo in particular has got me up to speed with his excellent range of posts](https://www.simoahava.com/analytics/server-side-tagging-google-tag-manager/).  This post will assume you've read those, and be more about the viability of deploying GTM server side within Cloud Run.

Many thanks to Adam Halbardier @ Google in the GTM serverside google group who helped guide me through the below.

## Why GTM Serverside on Cloud Run?

The current supported production deployment for GTM server side is to App Engine Flexible, which supports Docker containers.  

I have gone through my own journey up the Cloud stack with R deployments and briefly considered App Engine Flexible as an option for R APIs, but it got superseded when Cloud Run appeared.  The private beta of GTM server side used Kubernetes, which demonstrated that the platform running the container is flexible, so it encouraged trying other Docker based deployments on GCP.  This flexibility is also good to make it deployable to other clouds if you need to. 

Cloud Run deployments are not initially supported by the GTM beta so should not be considered in production, but I hope that it will be in the future.  The main advantages for me are:

* Scale-to-zero - App Engine Flexible does not scale to zero, so you have a minimum charge of at least 1 VM per month and as its recommended to use 3 VMs this is $120 per month.  App Engine Standard does scale-to-zero, but is recommended by Google only for debug and testing purposes.
* Cost - this will alter given the number of hits per month, but initial thoughts are that if you are under 1Million hits per month then Cloud Run should be cheaper compared to $120 a month for App Engine Flexible.
* Performance - I'm only running this on my blog at the moment so it may differ for lots of traffic and heavy tag use, but running similar GTM containers on App Engine and Cloud Run look to be at least comparable and in my tests Cloud Run is 50% quicker in responses - below `gtm2.markedmmondson.me` requests are to Cloud Run (91ms), `gtm.markedmondson.me` are to App Engine Standard (250ms)

![](/images/gtm-requests.png)

This needs to be taken with a pinch of salt until run on larger websites.  At the GCP end, for me the App Engine had latencies around 77.25 ms compared to 24ms for Cloud Run, with the rest of the time seen on the website waterfall charts taken up by networking speed I guess.

* Ease of deployment - App Engine flexible although supported by a Google shell script is more complicated if you want to customise it - read through what the [shell script does](https://googletagmanager.com/static/serverjs/setup.sh) (right click and "Save Link As" to text for examination) as an example. In my experience if you don't need to work-around Cloud Run limitations then deploying and updating is simpler in Cloud Run.


## Why not GTM Serverside on Cloud Run?

Currently its a bit awkward to have the debug container displayed in the GTM interface - this is because debug requests go to `/gtm/*` on a debug specified container, and Cloud Run does not support routing requests to folders.  

There are work-arounds, but that makes it deployment more convoluted, but hopefully GTM serverside container will be easier to support different platforms, to make it not only more compatible with Cloud Run but other cloud services such as AWS and Azure container services. 

The costs for high volume websites as well may be more for Cloud Run once the bill goes over $120.  The best I can figure out from my limited running so far it works out around 1USD for 10000 requests so it may only make sense for websites under 1million hits per month.  But this is work in progress, will update here once I know more.

## How to deploy GTM Serverside to Cloud Run

When considering the Cloud Run configuration, you can refer to the deployment script given in the documentation for upgrading to a App Engine flexible service.  The most critical information you need is the docker image it deploys, which at time of writing is `gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable`

This container runs the node.js as developed by the GTM team.  As Adam writes, you can examine the application in the Docker container like so to see how you can configure it:

```sh
$ docker pull gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable
$ docker images
$ docker run <image id> /bin/bash -c "node server_bin.js --help"

Usage: node server_bin.js [options]

For options that can be set via either command-line flag or an environment variable, the command-line flag value takes precedence.

Options:

  --container_config: Base64-encoded container parameters in the URL query string format. This flag is required to be set. May also be set by CONTAINER_CONFIG environment variable. (default: undefined)

  --[no]run_as_debug_server: Enable when the server should run as a debug server. See the documentation for additional details. May also be set by RUN_AS_DEBUG_SERVER environment variable. (default: false)

  --container_refresh_seconds: Interval between container refreshes. May also be set by CONTAINER_REFRESH_SECONDS environment variable. (default: 60) (an integer)

  --host: Host on which to bind. Set the value to empty string to listen on the unspecified IPv6 address (::) if available, or the unspecified IPv4 address (0.0.0.0) otherwise. May also be set by HOST environment variable. (default: "")

  --port: Port to listen on. May also be set by PORT environment variable. (default: 8080)(an integer)

  --debug_message_expiration_seconds: Number of seconds after which an unread debug message is deleted. This flag is applicable only when running as the debug server. May also be set by DEBUG_MESSAGE_EXPIRATION_SECONDS environment variable. (default: 600) (an integer)

  --policy_script_url: HTTPS URL from which to load the policy script. May also be set by POLICY_SCRIPT_URL environment variable. (default: undefined)

  --policy_script_refresh_seconds: Interval between policy script refreshes. May also be set by POLICY_SCRIPT_REFRESH_SECONDS environment variable. (default: 60) (an integer)
```

For our initial purposes, the most pertinent is the `CONTAINER_CONFIG` env arg, which is how the Docker image knows which GTM serverside its working for.  Its also good to see that `PORT` is configurable as well, as that is a recommended setting for Cloud Run.

### Cloud Run setup

For initial deployment I tried to copy the resource requirements from the [App Engine Flexible configuration that you can read about here](https://developers.google.com/tag-manager/serverside/script-user-guide).  From the shell script there we have enough to configure Cloud Run:

* Container image URL: `gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable`
* Container port: Leave as `8080`
* Capacity: To match the App Engine flex configuration I set this to `512MiB`
* CPU Allocated: Leave as `1`
* Request timeout: Leave as `300`
* Maximum requests per container: Set to max `80` which mirrors App Engine flexible 100 requests per VM.
* Variables (second tab): 
  * `CONTAINER_CONFIG` = `{ContainerId given to you on GTM Serverside setup}`
  
It should look a bit like below:

![](/images/cloudrun-gtm-setup.png)

Once the Cloud Run is running with a green tick you should have a URL you could use, but for cookies its better for it to be running on a subdomain of your website domain.  This involves going to the [Domain Mappings in Cloud Run](https://console.cloud.google.com/run/domains) and verifying your domain with Search Console then selecting the subdomain.  A https certificate will be created for you, and after you have changed your DNS settings via a CNAME record you can then use the new URL in your GTM serverside tags.

![](/images/cloudrun-domain-mapping.png)

## Summary

If cheap enough I can see Cloud Run being the preferred method for small blogs like this one, and any website with less than $120 worth of App Engine traffic.  It may even be an option above that if the performance remains better.  At the very least it shows how with opening up GTM to Cloud environments how much customisation can be performed beyond just measurement so you have total control over your analytics setup. 
