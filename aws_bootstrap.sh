# #!/usr/bin/env bash
set -x
# # # https://github.com/opendatakit/opendatakit/wiki/Aggregate-AWS-Install
# # # TODO: update Tomcat config to reflect ODK_AGGREGATE settings (13. Configure Tomcat)

# Variables
BASE_DIR=$PWD
source "$BASE_DIR/secrets.sh"
ODK_DB_NAME=odk_prod
ODK_DB_HOSTNAME=localhost
ODK_DB_USERNAME=odk_user
ODK_HOSTNAME="ec2-52-71-254-104.compute-1.amazonaws.com"
ODK_PORT="8080"
ODK_SECUREPORT="8443"
ODK_SUPERUSER="sjh293@cornell.edu"
ODK_SUPERUSERNAME="cornelltech"

echo -e "\n--- Beginning software install. ---\n"
apt-get update > /dev/null 2>&1

echo -e "\n--- Installing OpenJDK ---\n"
apt-get install -y default-jdk > /dev/null 2>&1

echo -e "\n--- Futzing with ODKAggregate configuration ---\n"
ODK_SRC_TMP="$BASE_DIR/odkagg_src_tmp"
ODK_SETTINGS_TMP="$BASE_DIR/odkagg_settings_tmp"
ODK_BACKUP="$BASE_DIR/odk_backup"

mkdir -p $ODK_SETTINGS_TMP
mkdir -p $ODK_SRC_TMP
mkdir -p $ODK_BACKUP

pushd $ODK_SRC_TMP
# # Decompress the ODK war file
jar -xvf $BASE_DIR/ODKAggregate.war

pushd $ODK_SETTINGS_TMP
# Decompress the ODK settings file into a tmp directory
jar -xvf $ODK_SRC_TMP/WEB-INF/lib/ODKAggregate-settings.jar > /dev/null 2>&1
PORT_REGEX="s|^(security.server.port=)([0-9]+)|\1$ODK_PORT|"
SECUREPORT_REGEX="s|^(security.server.securePort=)([0-9]+)|\1$ODK_SECUREPORT|"
HOST_REGEX="s|^(security.server.hostname=)([A-Za-z\.0-9]+)|\1$ODK_HOSTNAME|"
SUPERUSER_REGEX="s|^(security.server.superUser=).*|\1mailto:$ODK_SUPERUSER|"
SUPERUSERNAME_REGEX="s|^(security.server.superUserUsername=).*|\1$ODK_SUPERUSERNAME|"
sed -E -i.bak $PORT_REGEX security.properties
sed -E -i.bak $SECUREPORT_REGEX security.properties
sed -E -i.bak $HOST_REGEX security.properties
sed -E -i.bak $SUPERUSER_REGEX security.properties
sed -E -i.bak $SUPERUSERNAME_REGEX security.properties
cat security.properties > $ODK_BACKUP/security_properties_debug.out

DB_URL_REGEX="s|^(jdbc.url=jdbc:mysql://127.0.0.1/)(.+)(\?autoDeserialize=true)|\1"$ODK_DB_NAME"\3|"
DB_USERNAME_REGEX="s|^(jdbc.schema=).*|\1$ODK_DB_NAME|"
DB_PASSWORD_REGEX="s|^(jdbc.password=).*|\1"$ODK_USER_PASSWORD"|"
DB_SCHEMA_REGEX="s|^(jdbc.username=).*|\1$ODK_DB_USERNAME|"
sed -E -i.bak $DB_URL_REGEX jdbc.properties
sed -E -i.bak $DB_USERNAME_REGEX jdbc.properties
sed -E -i.bak $DB_PASSWORD_REGEX jdbc.properties
sed -E -i.bak $DB_SCHEMA_REGEX jdbc.properties
cat jdbc.properties > $ODK_BACKUP/jdbc_properties.out

rm -f  *.bak
jar cf $ODK_BACKUP/ODKAggregate-settings.jar ./* > /dev/null 2>&1
popd

mv -f $ODK_BACKUP/ODKAggregate-settings.jar $ODK_SRC_TMP/WEB-INF/lib/ODKAggregate-settings.jar
jar -cvf $ODK_BACKUP/ODKAggregate.war *  > /dev/null 2>&1
popd

rm -rf $ODK_SRC_TMP $ODK_SETTINGS_TMP

echo -e "\n--- Installing Tomcat6 ---\n"
apt-get install -y tomcat6 > /dev/null 2>&1
apt-get install -y tomcat6-docs tomcat6-admin tomcat6-examples > /dev/null 2>&1

# Create the environment variables required for Tomcat
CATALINA_HOME="/usr/share/tomcat6"
JAVA_HOME="/usr/lib/jvm/default-java"
echo "CATALINA_HOME=$CATALINA_HOME" >> /etc/environment
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment
echo "JAVA_HOME=$JAVA_HOME" >> $CATALINA_HOME/bin/setenv.sh

echo -e "\n--- ODKAggregate Deployment With Tomcat ---\n"
rm -rf /var/lib/tomcat6/webapps
[ -d /var/lib/tomcat6/webapps ] || mkdir /var/lib/tomcat6/webapps
cp $ODK_BACKUP/ODKAggregate.war /var/lib/tomcat6/webapps/ROOT.war
chown -R tomcat6:tomcat6 /var/lib/tomcat6/

rm -rf $ODK_BACKUP

echo -e "\n--- Installing Ant, Git, Tar, Curl ---\n"
apt-get install -y ant git tar curl > /dev/null 2>&1

echo -e "\n--- Installing MySQL and settings ---\n"
debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"
apt-get install -y mysql-server > /dev/null 2>&1

echo -e "\n--- Installing expect for mysql_secure_installation ---\n"
apt-get install -y expect > /dev/null 2>&1

# Complements to the internet
# https://stackoverflow.com/questions/24270733/shell-script-automate-mysql-secure-installation-with-echo-command
echo -e "\n--- Executing mysql_secure_installation ---\n"
$(expect -c "
  set timeout 10
  spawn mysql_secure_installation
  expect \"Enter current password for root (enter for none):\"
  send \"$MYSQL_ROOT_PASSWORD\r\"
  expect \"Change the root password?\"
  send \"n\r\"
  expect \"Remove anonymous users?\"
  send \"y\r\"
  expect \"Disallow root login remotely?\"
  send \"y\r\"
  expect \"Remove test database and access to it?\"
  send \"y\r\"
  expect \"Reload privilege tables now?\"
  send \"y\r\"
  expect eof
")
echo -e "\n--- Purging expect ---\n"
apt-get purge -y expect

echo -e "\n--- Creating ODK MySQL database and user ---\n"
mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD ping
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $ODK_DB_NAME"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$ODK_DB_USERNAME'@'$ODK_DB_HOSTNAME' IDENTIFIED BY '"$ODK_USER_PASSWORD"'"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $ODK_DB_NAME.* TO '$ODK_DB_USERNAME'@'$ODK_DB_HOSTNAME' IDENTIFIED BY  '"$ODK_USER_PASSWORD"'"
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES"
mysqladmin -u$ODK_DB_USERNAME -p$ODK_USER_PASSWORD ping
service mysql restart

echo -e "\n--- Adding Connector-J to Tomcat6 lib ---\n"
CONNECTORJ_FILENAME="mysql-connector-java-5.1.36"
CONNECTORJ_TAR="$CONNECTORJ_FILENAME.tar.gz"
# https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.36.tar.gz
curl -OL https://dev.mysql.com/get/Downloads/Connector-J/$CONNECTORJ_TAR > /dev/null 2>&1
tar -xzf $CONNECTORJ_TAR
cp $(find . -iname "mysql-connector*.jar") /usr/share/tomcat6/lib/
rm -rf $CONNECTORJ_TAR $CONNECTORJ_FILENAME

service tomcat6 restart
