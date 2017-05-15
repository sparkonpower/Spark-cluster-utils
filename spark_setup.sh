#!/bin/bash -l

CURDIR=`pwd`
WORKDIR=${HOME}

current_time=$(date +"%Y.%m.%d.%S")

if [ ! -d $CURDIR/logs ];
then
    mkdir logs
fi

log=`pwd`/logs/spark_setup_$current_time.log
echo -e | tee -a $log
#MASTER=$1
MASTER=$(ssh $1 "hostname")
#SLAVES=`echo $2 | tr "," "%"`
SLAVES=`cat ${HADOOP_HOME}/etc/hadoop/slaves | tr "\n" "%"`
#Logic to create server list 
echo $SLAVES | tr "%" "\n" | grep $MASTER 
if [ $? -eq 0 ]
then
    #if master is also used as data machine 
    SERVERS=$SLAVES
else
    SERVERS=`echo ''$MASTER'%'$SLAVES''`
fi
##backing the hive-site.xml file

echo "Backing up the config files hive-site.xml and spark-defaults.conf"
cp ${SPARK_HOME}/conf/hive-site.xml ${WORKDIR}
cp ${SPARK_HOME}/conf/spark-defaults.conf ${WORKDIR}

SPARK_DIR=`ls -ltr ${WORKDIR}/spark-*-bin-hadoop-*.tgz | tail -1 | awk '{print $9}' | sed 's/.tgz//'` 
SPARK_FILE=`ls -ltr ${WORKDIR}/spark-*-bin-hadoop-*.tgz | tail -1 | awk '{print $9}'` 
if [ $? -ne 0  ];
then
    echo "Spark tgz file does not exist. Please rerun the spark validation job to generate again." | tee -a $log
    exit 1
   echo "***********************************************"
fi

## Exporting SPARK_HOME to the PATH and Add scripts to the PATH

for i in `echo $SERVERS | tr "%" "\n"`
do

    if [ $i != $MASTER ]
	then
	    echo 'Deleting old spark file and copying new Spark setup file on '$i'' | tee -a $log
		ssh $i "rm ${SPARK_FILE}" 
	    scp ${SPARK_FILE} @$i:${WORKDIR} | tee -a $log
	fi
	
	ssh $i '[ -d '${SPARK_DIR}' ]' 
	if [ $? -eq 0 ]
		then 
		echo 'Deleting existing spark folder '$SPARK_DIR'  from '$i' '| tee -a $log
		ssh $i "rm -rf ${SPARK_DIR}" 
	fi
	
	echo 'Unzipping Spark setup file on '$i'' | tee -a $log
    ssh $i "tar xf ${SPARK_FILE} --gzip" | tee -a $log	
	
	echo 'Updating .bashrc file on '$i' with Spark variables '	
	echo '#StartSparkEnv' >tmp_b
	echo "export SPARK_HOME="${SPARK_DIR}"" >>tmp_b
	echo "export PATH=\$SPARK_HOME/bin:\$PATH">>tmp_b
	echo '#StopSparkEnv'>>tmp_b
		
	scp tmp_b @$i:${WORKDIR}
		
	ssh $i "grep -q "SPARK_HOME" ~/.bashrc"
	if [ $? -ne 0 ];
	then
	    ssh $i "cat tmp_b>>$HOME/.bashrc"
	    ssh $i "rm tmp_b"
	else
	    ssh $i "sed -i '/#StartSparkEnv/,/#StopSparkEnv/ d' $HOME/.bashrc"
	    ssh $i "cat tmp_b>>$HOME/.bashrc"
		ssh $i "rm tmp_b"
	fi

	ssh $i "source $HOME/.bashrc"
    echo "---------------------------------------------" | tee -a $log			
done
rm -rf tmp_b



##Exporting spark variables for current script session on master
export SPARK_HOME=${SPARK_DIR}
export PATH=$SPARK_HOME/bin:$PATH


## updating Slave file for Spark folder
source ${HOME}/.bashrc
echo 'Updating Slave file for Spark setup'| tee -a $log

cp ${SPARK_HOME}/conf/slaves.template ${SPARK_HOME}/conf/slaves
sed -i 's|localhost||g' ${SPARK_HOME}/conf/slaves
cat ${HADOOP_HOME}/etc/hadoop/slaves>>${SPARK_HOME}/conf/slaves

#setting spark log properties to display only errors
cp $SPARK_HOME/conf/log4j.properties.template $SPARK_HOME/conf/log4j.properties
sed -i 's/^log4j.rootCategory.*/log4j.rootCategory=ERROR, console/g' $SPARK_HOME/conf/log4j.properties

##Restoring hive-site.xml in conf dir under SPARK_HOME
echo "Restoring config files spark-defaults.conf and hive-site.xml in spark folder"
for i in `echo $SERVERS |tr "%" "\n"`
do
	scp $SPARK_HOME/conf/log4j.properties @$i:$SPARK_HOME/conf | tee -a $log
	scp $WORKDIR/spark-defaults.conf @$i:$SPARK_HOME/conf | tee -a $log
	scp $WORKDIR/hive-site.xml @$i:$SPARK_HOME/conf | tee -a $log
done

echo -e "Spark installation done..!!\n" | tee -a $log
echo -e 
