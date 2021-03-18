#!/bin/bash

cd /app
if [ -e ./.env]; then
    source .env
fi

env
python runserver.py