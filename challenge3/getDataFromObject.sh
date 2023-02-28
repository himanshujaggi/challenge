#! /bin/bash

##########################################################
##########################################################
##   script: getDataFromObject.sh
##   Author: Himanshu Jaggi
##   Date: 28-03-2023
##   Description: This script prints the value of the key provided                             
##   Usage: sh "<script_path>"                                              
##                                                       
###########################################################                                                     
###########################################################


OBJECT='{"x":{"y":{"z":"a"}}}'
KEY='x/y/z'

KEY=`echo $KEY | tr / .`


echo $OBJECT | jq .$KEY