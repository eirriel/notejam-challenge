FROM python:2.7-stretch

ADD . /app
WORKDIR /app
RUN apt update && apt install python-mysqldb && \
    pip install -r requirements.txt && \
    pip install MySQL-python

EXPOSE 5000
CMD ["python","runserver.py"]