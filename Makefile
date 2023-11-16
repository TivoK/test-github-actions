.ONESHELL:
SHELL=/bin/bash

PYTHON_VERSION := 3.10.6
VIRTUALENV_NAME := data-lake
PYENV_ROOT := $(shell pyenv root)
BUILD := build

GLUE_PATH := .glue
SPARK_VERSION := spark-3.1.1-amzn-0-bin-3.2.1-amzn-3
SPARK_PACKAGE := https://aws-glue-etl-artifacts.s3.amazonaws.com/glue-3.0/$(SPARK_VERSION).tgz
AWS_GLUE_PACKAGE := https://github.com/awslabs/aws-glue-libs/archive/refs/tags/v3.0.tar.gz

AVRO_VERSION := spark-avro_2.12-3.1.1.jar
SPAK_AVRO_JAR := https://repo1.maven.org/maven2/org/apache/spark/spark-avro_2.12/3.1.1/$(AVRO_VERSION)
DELTA_VERSION := delta-core_2.12-1.0.0.jar
SPARK_DELTA_JAR := https://repo1.maven.org/maven2/io/delta/delta-core_2.12/1.0.0/$(DELTA_VERSION)

SPARK_HOME := $(GLUE_PATH)/$(SPARK_VERSION)
SPARK_JARS := $(GLUE_HOME)/jars
SPARK_CONF := $(SPARK_HOME)/conf/spark-defaults.conf

GLUE_LIB_HOME=$(GLUE_PATH)/aws-glue-libs-3.0

.PHONY: virtualenv pip-update lint clean test test-jobs test-cdk deploy-preprod deploy-production

default: lint test

$(BUILD):
	mkdir -p $(BUILD)

${PYENV_ROOT}/versions/${PYTHON_VERSION}:
	pyenv install -s ${PYTHON_VERSION}
	# pip install --upgrade pip

${PYENV_ROOT}/versions/${VIRTUALENV_NAME}: ${PYENV_ROOT}/versions/${PYTHON_VERSION}
	pyenv virtualenv ${PYTHON_VERSION} ${VIRTUALENV_NAME}
	(source ${PYENV_ROOT}/versions/${VIRTUALENV_NAME}/bin/activate && python3 --version \
	 && pip install --upgrade pip \
	 && pip install pip-tools -r pip-tools.txt)


pip-tools.txt: pip-tools.in
	pip-compile pip-tools.in

requirements.txt: pip-tools.txt requirements.in
	pip-compile

dev-requirements.txt: requirements.txt dev-requirements.in
	pip-compile dev-requirements.in

pip-update: pip-tools.txt requirements.txt dev-requirements.txt
	(if [ -n "$$PYENV_ROOT" ]; then \
		source ${PYENV_ROOT}/versions/${VIRTUALENV_NAME}/bin/activate && python3 --version \
		&& pip install --upgrade pip \
		&& pip install --upgrade pip-tools \
		&& pip-sync pip-tools.txt requirements.txt dev-requirements.txt \
	else
		pip install --upgrade pip \
		&& pip install --upgrade pip-tools \
		&& pip-sync pip-tools.txt requirements.txt dev-requirements.txt \
	fi && \
	)
	

virtualenv: ${PYENV_ROOT}/versions/${VIRTUALENV_NAME} pip-update

$(GLUE_PATH):
	mkdir -p $(GLUE_PATH)

$(GLUE_PATH)/$(SPARK_VERSION): | $(GLUE_PATH)
	curl -s $(SPARK_PACKAGE) | tar xvf - -C $(GLUE_PATH)

$(GLUE_LIB_HOME): | $(GLUE_PATH)
	curl -sL $(AWS_GLUE_PACKAGE) | tar xvfz - -C $(GLUE_PATH)

$(SPARK_CONF): $(SPARK_HOME)
	curl -s $(SPAK_AVRO_JAR) -o $(SPARK_HOME)/jars/$(AVRO_VERSION)
	curl -s $(SPARK_DELTA_JAR) -o $(SPARK_HOME)/jars/$(DELTA_VERSION)
	echo "spark.driver.extraClassPath ${SPARK_JARS}/*" > $(SPARK_CONF)
	echo "spark.executor.extraClassPath ${SPARK_JARS}/*" >> $(SPARK_CONF)

dependencies: $(SPARK_CONF) $(GLUE_LIB_HOME)

add-jars:
	rm -f $(SPARK_HOME)/.add_jars && touch $(SPARK_HOME)/.add_jars 

lint:
	flake8 src tests

clean:
	find {src,tests} -type f -name '*.py[co]' -delete -o -type d -name __pycache__ -delete

test-glue:
	pytest tests/glue/jobs

test-cdk:
	pytest tests/cdk

test-schema:
	pytest tests/schema

test-lambda:
	pytest tests/lambda; \
	 $(MAKE) -C src/lambda/stockroom

test: test-glue test-cdk test-schema test-lambda


deploy-preprod:
	cdk deploy 'Preprod*' --profile preprod

deploy-production:
	cdk deploy 'Production*' --profile production

diff-preprod:
	cdk diff 'Preprod*' --profile preprod

diff-production:
	cdk diff 'Production*' --profile production

synth:
	cdk synth


deploy-all: deploy-preprod deploy-production
