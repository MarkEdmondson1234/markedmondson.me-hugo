---
title: Auto Google Analytics Data Imports from Cloud Storage
author: Mark Edmondson
date: '2018-11-29'
slug: automatic-google-analytics-data-imports-cloud-storage
tags:
  - google-cloud-storage
  - python
  - google-analytics
  - cloud-functions
banner: banners/data-imports.jpg
description: 'Use Google Cloud Functions to auto-load your data imports into Google Analytics form Cloud Storage'
---

Continuing my infatuation with cloud functions (see last post on using cloud functions to manipulate BigQuery exports) this is a post showing how to bring together various code examples out there so that you can easily upload custom data imports from a Google cloud storage bucket.

The code is available in this [GitHub repo for useful cloud functions with Google Analytics](https://github.com/MarkEdmondson1234/google-analytics-cloud-functions)

## Extended data imports

Google Analytics offers various versions of uploads.


<iframe width="560" height="315" src="https://www.youtube.com/embed/leqMQK-cuwk" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

This post is about the [user level extended-data imports](https://support.google.com/analytics/answer/6066725).

For these imports you can do historic and [query time](https://support.google.com/analytics/answer/6071511?hl=en&ref_topic=6064627) (if you are using GA360).  

Historic data imports can't be changed once uploaded as they are joined with the data upon **collection**, so suits things like date of birth (which shouldn't change per user).  

Query time imports join with the data at the time you **request** the data, so can be used for more dynamic data such as which segment that user is in at the time.  That data could be computed offline in your CRM database or similar, and then made available to Google Analytics so you can create segments for Google Ads or Google Optimize.  You can do a lot more interesting things with it, which is why its a GA360 feature.  

## Why automate uploads?

You can upload the data manually via the Google Analytics web UI, but when it comes to query time imports that can change often, that could mean daily updates.  It also takes a few hours to be available, so the earlier you can do it the better.  

Both these requirements make it a good fit for cloud functions, since you can create a trigger that will run as soon as the data is available (not on a schedule) and trigger on demand.

## Why use Google Cloud Storage?

Google Cloud Storage is a generic blob store of bytes that is very quick and can hold many TBs of data.  It has many APIs and integrations (including [googleCloudStorageR](http://code.markedmondson.me/googleCloudStorageR/) ) with the rest of the Google Cloud Platform and beyond, and I treat it as the central backbone for all my data storage.  
The idea is if the Cloud Function can take care of the link between Cloud Storage and Google Analytics, then its flexible how that file arrives at Cloud Storage.  It could be an R script, a BigQuery extract or an Airflow DAG that puts the file in the bucket, but once its there you know it will be uploaded to Google Analytics. 

## Preparation

### Create the Google Analytics custom data import

Within the Google Analytics Web UI, you need to create the custom data import's specifications.  In this case it would be a user custom data upload, query time and you then specify the key you are joining with, along with which dimensions you want to populate for that user.  Usually these are custom dimensions you have also previously created. 

Once created you should get a schema you will use to create the correct data, and a custom upload ID that you will use within the upload script.

### Create an authentication file

To run the script, since it deals with Google Analytics you need to create a service authentication file the script can use to allow it access to upload data.  You don't normally need this if using Google cloud services such as BigQuery, as the authentication is baked in, but as Google Analytics is not a cloud product, in this case we do. 

1. Reuse or create a Google Cloud Project with billing enabled.
2. Service accounts can be created [here](https://console.cloud.google.com/iam-admin/serviceaccounts/create)
3. It does not need any GCP account permissions (we do that in next step when we add to GA)
4. Create a JSON key for that service account and download it somewhere safe calling it `auth.json`
5. Copy the service email e.g. `ga-uploads@your-project.iam.gserviceaccount.com`
6. Login to Google Analytics and add the user at Web Property level with **Edit** permissions.
7. Make sure the GCP project the service key is for has Analytics API access enabled.

You should now be able to use the JSON auth file to authenticate with Google Analytics API.

### Create a Google Cloud Storage bucket

Now we will create a Google Cloud storage bucket, and upload the authentication file to it.  We do this instead of uploading the authentication file with the Cloud function, as it keeps the Cloud function generic enough you can use it for other accounts by just pointing at a different bucket when you deploy. 

You create a bucket from [here](https://console.cloud.google.com/storage/browser) once you have your Google Cloud Project. 

Once you have your bucket upload the `auth.json` file to the bucket, and then create a folder within the bucket which is where your uploads will be delivered to,

## The code

The code is available in this [GitHub repo for useful cloud functions with Google Analytics](https://github.com/MarkEdmondson1234/google-analytics-cloud-functions) which you can clone, modify and use. 

You will need to specify the `pip` requirements for your code in a `requirements.txt` file, but you don't have to actually upload the libraries as you do for say App Engine.  Cloud Functions will download them for you when you deploy.

Create a `requirements.txt` file with these pinned dependencies:

```
google-api-python-client==1.7.4
google-cloud-storage==1.13.0
oauth2client==4.1.3
```

The full script to upload to Cloud functions after you fill in your details is below.  It should be saved to a file called `main.py`

```python
import logging
import base64
import json
import os
from urllib.error import HTTPError
from apiclient.discovery import build
from oauth2client.service_account import ServiceAccountCredentials
from apiclient.http import MediaFileUpload
from google.cloud import storage

# set these to your details
ACCOUNTID='123456'
WEBPROPERTYID='UA-123456-2'
CUSTOM_DATASOURCE_ID='data_source_id'
FOLDER='source_folder_in_gcs_bucket'

# save file to /tmp only as cloud functions only supports that to write to
def download_gcs_file(obj, to, bucket):
    client = storage.Client()
    bucket = client.get_bucket(bucket)
    blob = bucket.blob(obj)

    blob.download_to_filename(to)
    logging.debug('downloaded file {} to {}'.format(obj, to))

# needs an auth.json file as cloud auth not working for analytics requests
def get_ga_service(bucket):

    download_gcs_file('auth.json', '/tmp/auth.json', bucket)
    credentials = ServiceAccountCredentials.from_json_keyfile_name(
            '/tmp/auth.json',
            scopes=['https://www.googleapis.com/auth/analytics',
                    'https://www.googleapis.com/auth/analytics.edit'])

    # Build the service object.
    return build('analytics', 'v3', credentials=credentials, cache_discovery=False)

def upload_ga(obj_name, bucket):

    filename = '/tmp/{}'.format(os.path.basename(obj_name))

    download_gcs_file(obj_name, filename, bucket)

    analytics = get_ga_service(bucket)

    try:
      media = MediaFileUpload(filename,
                              mimetype='application/octet-stream',
                              resumable=False)

      daily_upload = analytics.management().uploads().uploadData(
          accountId=ACCOUNTID,
          webPropertyId=WEBPROPERTYID,
          customDataSourceId=CUSTOM_DATASOURCE_ID,
          media_body=media).execute()

      logging.info('Uploaded file: {}'.format(json.dumps(daily_upload)))

    except TypeError as error:
      # Handle errors in constructing a query.
      logging.error('There was an error in constructing your query : {}'.format(error))

    except HTTPError as error:
      # Handle API errors.
      logging.error('There was an API error : {} : {}'.format(error.resp.status, error.resp.reason))

    return

def gcs_to_ga(data, context):
    """Background Cloud Function to be triggered by Pub/Sub subscription.
       This functions copies the triggering BQ table and copies it to an aggregate dataset.
    Args:
        data (dict): The Cloud Functions event payload.
        context (google.cloud.functions.Context): Metadata of triggering event.
    Returns:
        None; the output is written to Stackdriver Logging
    """
    logging.info('Bucket: {} File: {} Created: {} Updated: {}'.format(data['bucket'],
                                                                      data['name'],
                                                                      data['timeCreated'],
                                                                      data['updated']))
    folder = FOLDER
    object_name = data['name']
    bucket = data['bucket']
    if object_name.startswith(folder):
      logging.info('File matches folder {}'.format(folder))

      upload_ga(object_name, bucket)
      
    return
```

A walk-through of the functions is below:

### Handling pub/sub functions

This function is the main entry point of the code.  When a new file arrives on Google Cloud Storage, it creates a Pub/Sub trigger with the meta data of the file and sends it to the trigger we will create when we deploy.

The `FOLDER` variable is so you can limit the function triggering to just a specific folder on the Google Cloud Bucket.  This is convenient so you can make sure only upload files trigger the function, and not say the authentcation files.

```python
def gcs_to_ga(data, context):
    """Background Cloud Function to be triggered by Pub/Sub subscription.
       This functions copies the triggering BQ table and copies it to an aggregate dataset.
    Args:
        data (dict): The Cloud Functions event payload.
        context (google.cloud.functions.Context): Metadata of triggering event.
    Returns:
        None; the output is written to Stackdriver Logging
    """
    logging.info('Bucket: {} File: {} Created: {} Updated: {}'.format(data['bucket'],
                                                                      data['name'],
                                                                      data['timeCreated'],
                                                                      data['updated']))
    folder = FOLDER
    object_name = data['name']
    bucket = data['bucket']
    if object_name.startswith(folder):
      logging.info('File matches folder {}'.format(folder))

      upload_ga(object_name, bucket)
      
    return
```

### Downloading files from Google Cloud Storage

This code reuses the authentication of the function and downloads the file to it.  It can only download to the `/tmp` folder of the Cloud Function.

```python
def download_gcs_file(obj, to, bucket):
    client = storage.Client()
    bucket = client.get_bucket(bucket)
    blob = bucket.blob(obj)

    blob.download_to_filename(to)
    logging.debug('downloaded file {} to {}'.format(obj, to))
```

### Creating the Google Analytics object

This downloads the `auth.json` file from Cloud Storage, and uses it to create an authenticated session with Google Analytics:

```python
# needs an auth.json file as cloud auth not working for analytics requests
def get_ga_service(bucket):

    download_gcs_file('auth.json', '/tmp/auth.json', bucket)
    credentials = ServiceAccountCredentials.from_json_keyfile_name(
            '/tmp/auth.json',
            scopes=['https://www.googleapis.com/auth/analytics',
                    'https://www.googleapis.com/auth/analytics.edit'])

    # Build the service object.
    return build('analytics', 'v3', credentials=credentials, cache_discovery=False)
```


### Download from Cloud Storage and upload to GA

This does the work of downloading the file and uploading again to GA.  It uses the variables defined at the start of the script to determine where to upload it, but you could modify this to use a configuration file or loop over several uploads.

Code is adapted from [here](https://developers.google.com/analytics/devguides/config/mgmt/v3/mgmtReference/management/uploads/uploadData)

```python
def upload_ga(obj_name, bucket):

    filename = '/tmp/{}'.format(os.path.basename(obj_name))

    download_gcs_file(obj_name, filename, bucket)

    analytics = get_ga_service(bucket)

    try:
      media = MediaFileUpload(filename,
                              mimetype='application/octet-stream',
                              resumable=False)

      daily_upload = analytics.management().uploads().uploadData(
          accountId=ACCOUNTID,
          webPropertyId=WEBPROPERTYID,
          customDataSourceId=CUSTOM_DATASOURCE_ID,
          media_body=media).execute()

      logging.info('Uploaded file: {}'.format(json.dumps(daily_upload)))

    except TypeError as error:
      # Handle errors in constructing a query.
      logging.error('There was an error in constructing your query : {}'.format(error))

    except HTTPError as error:
      # Handle API errors.
      logging.error('There was an API error : {} : {}'.format(error.resp.status, error.resp.reason))

    return

```


## Deployment

 The full code above needs to be saved to a file called `main.py` and then put into the same folder as `requirements.txt`:

```
-|
 |- main.py
 |- requirements.txt
```

You may need to then install the `gcloud beta` components to deploy the python.  See the [guide](https://cloud.google.com/functions/docs/quickstart) here.

After you have it installed, browse to the folder holding your code in your console, and then issue the `gcloud` commands to deploy the files.  It takes around 2 mins.

You need to specify the function that will trigger.  In our case this is the function that receives the data, `def gcs_to_ga(data, context)`.  We also need to specify its a Python file, and what the trigger will be.

If the file to upload is big, then you may also need a bigger Cloud function instance than the default 256MB.  The max file size that can be uploaded to Google Analytics is 1GB, so the largest 2048MB cloud function should cover that - the `gcloud` below shows how to specify that size of function:

```sh
gcloud functions deploy gcs_to_ga --runtime python37 \
                                  --trigger-resource your-bucket \
                                  --trigger-event google.storage.object.finalize \
                                  --region europe-west1 \
                                  --memory=2048MB
```

## Summary

Upon successful deployment, you should be able to monitor the function in the [logs](https://console.cloud.google.com/logs/viewer).  Each time you upload a file to your bucket into the right folder, it will start a job to upload that file to Google Analytics.

It can take a couple of hours for the data to appear within Google Analytics reports.

This is a nice example of some functional "glue" that uncouples how to upload to GA from the file creation itself.  For example, it could be BigQuery exports that are creating the file, but that can switch to Airflow if the data transformations to create the files get more complicated or need special considerations.  The code is only intended as a starting point for you to customise and adapt to your needs. 





