#! /bin/python3

##########################################################
##########################################################
##   script: getDataFromObject.py
##   Author: Himanshu Jaggi
##   Date: 28-03-2023
##   Description: This script prints the value of the key provided                             
##   Usage: python3 "<script_path>"                                              
##                                                       
###########################################################                                                     
###########################################################


import json


OBJECT = '{"x":{"y":{"z":"a"}}}'
KEY = 'x/y/z'.strip("/")
KEY_DELIMITER="/"
JSON_DATA=json.loads(OBJECT)

def getData(obj,key):
    try:
        return obj[key]
    except KeyError:
        print("Error. No value found for the provided key.")
        raise

def main():
    sub_data =JSON_DATA
    for i in KEY.split(KEY_DELIMITER):
        sub_data =getData(sub_data,i.strip())
    if sub_data:
        print("Here is the value:",sub_data)
    else:
        print("Value is Null or not Defined")

main()