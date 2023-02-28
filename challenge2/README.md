##########################################################
##########################################################
##   script: getInstanceMetadata.sh
##   Author: Himanshu Jaggi
##   Date: 28-03-2023
##   Description: This takes 4 positional arguments and returns the Instance metadata in the Json format.
##   Arguments:
##             Position1:"Complete path of the service-account json key file for auhentication with GCP"                                          
##             Position2:"Name of the instance"                                
##             Position3:"Zone of the instance"                                
##             Position4:"particular data key to be retrieved"                                
##   Usage:./getInstanceMetadata.sh "/usr/local/service_account.json" "apd04-a" "us-east1-d" "name"                                               
##                                                       
###########################################################                                                     
###########################################################