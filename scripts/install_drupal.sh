#!/bin/bash
#set -x

is_quickstart="${is_quickstart}"
drupal_site="${drupal_site}"
drupal_account_name="${drupal_account_name}"
drupal_account_password="${drupal_account_password}"
drupal_schema="${drupal_schema}"
drupal_name="${drupal_name}"
drupal_password="${drupal_password}"
encoded_drupal_password=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$drupal_password")
mds_ip="${mds_ip}"

if [[ $is_quickstart == "true" ]]; then
  cd /var/www/
  # Changing code to use latest Drupal
  wget https://www.drupal.org/download-latest/tar.gz -O drupal.tar.gz
  tar zxvf drupal.tar.gz
  rm -rf html/ tar.gz
  mv drupal-* html
  cd html
  cp sites/default/default.settings.php sites/default/settings.php

  #install drush to install drupal thru CLI 
  php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
  php composer-setup.php --install-dir=/usr/local/bin --filename=composer
  echo "Executing user: $(whoami)"
  echo "PATH before: $PATH"
  export PATH=/usr/local/bin:$PATH
  echo "PATH after: $PATH"
  composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
  composer require drupal/core-recommended drupal/core-composer-scaffold drush/drush --no-interaction

  # Print all variables
  echo "drupal_name: $drupal_name"
  echo "encoded_drupal_password: $encoded_drupal_password"
  echo "mds_ip: $mds_ip"
  echo "drupal_schema: $drupal_schema"
  echo "drupal_site: $drupal_site"
  echo "drupal_account_name: $drupal_account_name"
  echo "drupal_account_password: $drupal_account_password"

  # Build and echo full command with expanded values
  full_cmd="vendor/bin/drush site:install standard --db-url='mysql://${drupal_name}:${encoded_drupal_password}@${mds_ip}/${drupal_schema}' --site-name='${drupal_site}' --account-name='${drupal_account_name}' --account-pass='${drupal_account_password}' --yes" 
  echo "Executing: $full_cmd"

  # Execute the command
  vendor/bin/drush site:install standard --db-url='mysql://${drupal_name}:$encoded_drupal_password@${mds_ip}/${drupal_schema}' --site-name='${drupal_site}' --account-name='${drupal_account_name}' --account-pass='${drupal_account_password}' --yes
  
  cd -
  chown apache. -R html
  sed -i '/AllowOverride None/c\AllowOverride All' /etc/httpd/conf/httpd.conf

else

  export use_shared_storage='${use_shared_storage}'

  if [[ $use_shared_storage == "true" ]]; then
    echo "Mount NFS share: ${drupal_shared_working_dir}"
    yum install -y -q nfs-utils
    mkdir -p ${drupal_shared_working_dir}
    echo '${mt_ip_address}:${drupal_shared_working_dir} ${drupal_shared_working_dir} nfs nosharecache,context="system_u:object_r:httpd_sys_rw_content_t:s0" 0 0' >> /etc/fstab
    setsebool -P httpd_use_nfs=1
    mount ${drupal_shared_working_dir}
    mount
    echo "NFS share mounted."
    cd ${drupal_shared_working_dir}
  else
    echo "No mount NFS share. Moving to /var/www/html"
    cd /var/www/
  fi

  # Changing code to use latest Drupal
  wget https://www.drupal.org/download-latest/tar.gz -O drupal.tar.gz

  if [[ $use_shared_storage == "true" ]]; then
    tar zxvf drupal.tar.gz --directory ${drupal_shared_working_dir}
    cp -r ${drupal_shared_working_dir}/drupal-*/* ${drupal_shared_working_dir}
    rm -rf ${drupal_shared_working_dir}/drupal-*
    cp ${drupal_shared_working_dir}/sites/default/default.settings.php sites/default/settings.php
  else
    tar zxvf drupal.tar.gz
    rm -rf html/ tar.gz
    mv drupal-* html
    cd html
    cp sites/default/default.settings.php sites/default/settings.php
  fi

  if [[ $use_shared_storage == "true" ]]; then
    echo "... Changing /etc/httpd/conf/httpd.conf with Document set to new shared NFS space ..."
    sed -i 's/"\/var\/www\/html"/"\${drupal_shared_working_dir}"/g' /etc/httpd/conf/httpd.conf
    echo "... /etc/httpd/conf/httpd.conf with Document set to new shared NFS space ..."
    chown apache:apache -R ${drupal_shared_working_dir}
    sed -i '/AllowOverride None/c\AllowOverride All' /etc/httpd/conf/httpd.conf
    cp /home/opc/htaccess ${drupal_shared_working_dir}/.htaccess
    rm /home/opc/htaccess
    cp /home/opc/index.html ${drupal_shared_working_dir}/index.html
    rm /home/opc/index.html
    chown apache:apache ${drupal_shared_working_dir}/index.html
  else
    cd -
    chown apache. -R html
    sed -i '/AllowOverride None/c\AllowOverride All' /etc/httpd/conf/httpd.conf
  fi
fi

systemctl start httpd
systemctl enable httpd

echo "Drupal installed and Apache started !"
