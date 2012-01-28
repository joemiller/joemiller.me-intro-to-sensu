I'm excited about [Sensu](http://www.sonian.com/cloud-tools/cloud-monitoring-sensu/), a new open source monitoring framework, and I'd like to help others get started with it as well. So, after observing the frequent questions from new visitors to #sensu on Freenode I thought perhaps the best way to do that is to write a blog article to help folks get started. If you still have questions after reading this, feel free to come by #sensu on Freenode.

In this article I will provide a brief overview of Sensu with some background, walk through a client and server install, and then I will show you how to add a check and a handler. This should lay the groundwork for future articles with more examples on how to get the most value out of Sensu in your infrastructure.

Before we start, I owe a huge thanks to [@jeremy_carroll](http://twitter.com/jeremy_carroll) for the many hours of work he put into building RPM's for Sensu. His work on packaging will undoubtedly save many folks quite a bit of time.

What is Sensu?
==============

Sensu is the creation of [@portertech](http://twitter.com/portertech) and his colleagues at [sonian.com](http://sonian.com). They have graciously open-sourced the project recently and made it available to all of us searching for a modern monitoring platform (or anyone searching for an alternative to Nagios.)

Sensu is often described as the "monitoring router". Most simply put, Sensu connects "check" scripts run across many nodes with "handler" scripts run on one or more Sensu servers. Checks are used, for example, to determine if Apache is up or down. Checks can also be used to collect metrics such as MySQL statistics. The output of checks is routed to one or more handlers. Handlers determine what to do with the results of checks. Handlers currently exist for sending alerts to Pagerduty, IRC, Twitter, etc. Handlers can also feed metrics into Graphite, Librato, etc. Writing checks and handlers is quite simple and can be done in any language.

Key details:

- Ruby 1.8.7+ (EventMachine, Sinatra, AMQP), RabbitMQ, Redis
- Excellent test coverage with continuous integration via [travis-ci](http://travis-ci.org/#!/sonian/sensu)
- Messaging oriented architecture. Messages are JSON objects.
- Ability to re-use existing Nagios plugins
- Plugins and handlers (think notifications) can be written in any language
- Supports sending metrics into various backends (Graphite, Librato, etc)
- Designed with modern configuration management systems such as Chef or Puppet in mind
- Designed for cloud environments
- Lightweight, less than 1200 lines of code

Components
==========
Sensu is made up of several small components. I won't go into too much detail about each of them here, as their purpose will become obvious when we get started, so here a few short descriptions:

sensu-server
------------
The server initiates checks on clients, receives the output of the checks feeds them to handlers. (As of version 0.9.2, clients can also execute checks that the server doesn't know about and the server will still process their results, more on these 'standalone checks' in a future article.)

Sensu-server relies on a Redis instance to keep persistent data. It also relies heavily (as do most sensu components) on access to rabbitmq for passing data between itself and sensu-client nodes.

sensu-client
------------
Run this on all of your systems that you want to monitor. Sensu-client will execute checks scripts (think `check_http`, `check_load`, etc) and return the results from these checks to sensu-server via rabbitmq.

sensu-api
------------
A REST API that provides access to various pieces of data maintained on the sensu-server in Redis. You will typically run this on the same server as your sensu-server or Redis instance. It is mostly used by internal sensu components at this time.

sensu-dashboard
---------------
Web dashboard providing an overview of the current state of your Sensu infrastructure and the ability to perform actions, such as temporarily silencing alerts.

Installing
==========
As you start to explore Sensu you will find that it was built from the start to be used in conjunction with a CM tool such as Chef or Puppet. However, for the purposes of this article I will walk through a simple manual install. 

This article covers installation of Sensu via RPM on CentOS-5 and CentOS-6. Debian/ubuntu and derivatives are not covered in this guide, but many of the same steps will apply. At this time there are no .deb packages for the Sensu components so you will have to install Sensu from gem (ie: `gem install sensu sensu-dashboard`). Hopefully soon we will have native .deb packages for the Sensu components.

You will probably want to use Sensu with Chef or Puppet soon after you get bootstrapped (of course you're already using a modern CM tool in your infrastructure anyway, right?) There are good [Chef](https://github.com/sonian/sensu/tree/master/dist/chef) and [Puppet](https://github.com/sonian/sensu/tree/master/dist/puppet) recipes in the github repos that can help you get going fairly quickly. There are also a few community members working on improving these pieces so should get even better over time.

Additionally, the original dev platform for Sensu was Ubuntu but work has been done to help make it a little more CentOS/RHEL-friendly. I'm going to use CentOS 5 and 6 in this article just because I'm more familiar with this platform than the debian/ubuntu family. In any case, it shouldn't matter too much because the purpose of this article is to show you Sensu.

We will use 2 nodes, one will be our server and the other will be a simple client, with the following bits on each:

Server:

- rabbitmq
- redis
- sensu-server / sensu-client / sensu-api / sensu-dashboard

Client:

- sensu-client

Install a Sensu server node
===========================

Install rabbitmq
----------------
We will base our approach on the rabbit install guide from here: [http://www.rabbitmq.com/install-rpm.html](http://www.rabbitmq.com/install-rpm.html)

(CentOS 5 only) We need to install both the EPEL-5 and epel-erlang yum repos. The EPEL-5 yum repo contains the older R12B version of Erlang which would work fine with rabbit except we wouldn't have access to SSL nor the web management plugins. Thus, we'll be installing a newer Erlang from the `epel-erlang` repo which provides R14B for cent5.

    sudo rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm
    sudo wget -O /etc/yum.repos.d/epel-erlang.repo http://repos.fedorapeople.org/repos/peter/erlang/epel-erlang.repo
    
(CentOS 6 only) Install the EPEL-6 yum repo which contains Erlang R14B:

    sudo rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-5.noarch.rpm

Install Erlang:

    sudo yum install erlang
    
Install RabbitMQ:

    sudo rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
    sudo rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/v2.7.1/rabbitmq-server-2.7.1-1.noarch.rpm

We need to make some SSL certs for our rabbitmq server and the sensu clients. I put a simple script up on [github](https://github.com/joemiller/joemiller.me-intro-to-sensu) to help with this. You'll want to change a few things in the `openssl.cnf` to for your organization if you use this in production. The script will generate a few files that we'll need throughout the guide, so keep them nearby.

    git clone git://github.com/joemiller/joemiller.me-intro-to-sensu.git
    cd joemiller.me-intro-to-sensu/
    ./ssl_certs.sh clean
    ./ssl_certs.sh generate

Configure RabbitMQ to use these SSL certs

    mkdir /etc/rabbitmq/ssl
    cp server_key.pem /etc/rabbitmq/ssl/
    cp server_cert.pem /etc/rabbitmq/ssl/
    cp testca/cacert.pem /etc/rabbitmq/ssl/
    
Create `/etc/rabbitmq/rabbitmq.config`:

    [
      {rabbit, [
        {ssl_listeners, [5671]},
        {ssl_options, [{cacertfile,"/etc/rabbitmq/ssl/cacert.pem"},
                       {certfile,"/etc/rabbitmq/ssl/server_cert.pem"},
                       {keyfile,"/etc/rabbitmq/ssl/server_key.pem"},
                       {verify,verify_peer},
                       {fail_if_no_peer_cert,true}]}
      ]}
    ].

Install the RabbitMQ webUI management console:

    rabbitmq-plugins enable rabbitmq_management

Set RabbitMQ to start on boot and start it up immediately:

    sudo /sbin/chkconfig rabbitmq-server on
    sudo /etc/init.d/rabbitmq-server start

Verify operation with the RabbitMQ Web UI: Username is "guest", password is "guest" - `http://<SENSU-SERVER>:55672`. Protocol amqp should be bound to port 5672 and amqp/ssl on port 5671.

Finally, let's create a `/sensu` vhost and a `sensu` user/password on our rabbit:

    rabbitmqctl add_vhost /sensu
    rabbitmqctl add_user sensu mypass
    rabbitmqctl set_permissions -p /sensu sensu ".*" ".*" ".*"

Install redis
-------------
At this point we already have the EPEL repo installed on our server so we will install EPEL's version of Redis. For Cent5 this will be a fairly old redis v2.0, and for Cent6 it will be v2.2. Both should work fine with Sensu.

    sudo yum install redis
    sudo /sbin/chkconfig redis on
    sudo /etc/init.d/redis start

Install ruby 1.8.7
------------------
(CentOS 5 only) Sensu needs ruby 1.8.7+ but CentOS-5 ships with older Ruby 1.8.5. We will use the ruby 1.8.7 rpm's from Opscode's Chef. See [this page on the Chef wiki](http://wiki.opscode.com/display/chef/Installing+Chef+Client+on+CentOS#InstallingChefClientonCentOS-InstallRuby) for additional details.

    sudo wget -O /etc/yum.repos.d/aegisco.repo http://rpm.aegisco.com/aegisco/el5/aegisco.repo
    
(CentOS 6) CentOS 6 ships with ruby 1.8.7 so we don't need any external repos.

Install Ruby packages;

    sudo yum install ruby ruby-ri ruby-rdoc ruby-shadow rubygems curl openssl-devel

Install Sensu components.
-------------------------
Now we are ready to install Sensu. We will install two rpms: `rubygem-sensu` and `rubygem-sensu-dashboard`. This will install four components: sensu-server, sensu-client, sensu-api, sensu-dashboard. Sensu servers use all of these and clients only use sensu-client.

We are going to use [@jeremy_carroll](http://twitter.com/jeremy_carroll)'s recently created yum repo to install Sensu via rpm. This repo contains sensu rpm's for both CentOS 5 and 6. It's awesome that Jeremy has taken the time to set this up and I hope we can use this as a basis for automating the building of rpms and debs for all releases of Sensu. Since this repo was setup pretty much as this blog was being written, it's possible that this repo will move to a different location in the future.

(CentOS 5 only)

    sudo rpm -Uvh http://yum.carrollops.com/el/5/sensu-release-1.noarch.rpm
    
(CentOS 6 only)

    sudo rpm -Uvh http://yum.carrollops.com/el/6/sensu-release-1.noarch.rpm

We need to ignore the rubygem rpm's that come from EPEL because they will conflict with the sensu rpm's. Edit your `/etc/yum.repos.d/epel.repo` file and add the following line to the [epel] section.

    exclude=rubygem*

Install and enable sensu service components:

    sudo yum install rubygem-sensu rubygem-sensu-dashboard
    sudo chkconfig sensu-server on
    sudo chkconfig sensu-api on
    sudo chkconfig sensu-client on
    sudo chkconfig sensu-dashboard on

Copy the SSL client key + cert that we created earlier into `/etc/sensu/ssl`

    cp client_key.pem client_cert.pem  /etc/sensu/ssl/

Next we need to configure sensu by editing `/etc/sensu/config.json`. For now we will create just enough config to start sensu. Later we will add checks and handlers. Note (for later use) that Sensu will also read json config snippets out of the  `/etc/sensu/conf.d` directory so you can piece together a config easily using your CM tool.

    {
      "rabbitmq": {
        "ssl": {
          "private_key_file": "/etc/sensu/ssl/client_key.pem",
          "cert_chain_file": "/etc/sensu/ssl/client_cert.pem"
        },
        "port": 5671,
        "host": "localhost",
        "user": "sensu",
        "password": "mypass",
        "vhost": "/sensu"
      },
      "redis": {
        "host": "localhost",
        "port": 6379
      },
      "api": {
        "host": "localhost",
        "port": 4567
      },
      "dashboard": {
        "host": "localhost",
        "port": 8080,
        "user": "admin",
        "password": "secret"
      }
    }

Configure `/etc/sensu/conf.d/client.json` for the current node:

    {
      "client": {
        "name": "sensu-server.dom.tld",
        "address": "10.0.0.1",
        "subscriptions": [ "test" ]
      }
    }

(CentOS 5 x86_64 only) With the current set of rpm's we need to add a path to the GEM_PATH in order to find a couple of the rubygems we installed. Run the following:

    echo "export GEM_PATH=\$GEM_PATH:/usr/lib64/ruby/gems/1.8" > /etc/profile.d/gem_path.sh
    . /etc/profile.d/gem_path.sh


Now let's try to start the Sensu components:

    sudo /etc/init.d/sensu-server start
    sudo /etc/init.d/sensu-api start
    sudo /etc/init.d/sensu-client start    
    sudo /etc/init.d/sensu-dashboard start    

If all goes well, the 4 processes mentioned above will be running and the dashboard will be accessible on `http://<SENSU SERVER>:8080`. Log files are available in `/var/log/sensu` in case anything is wrong.
    
    sensu    14249  0.0  3.4  92924 17648 ?        S    02:56   0:00 ruby /usr/bin/sensu-server ...
    sensu    14404  0.0  4.1 102172 20884 ?        S    03:05   0:00 ruby /usr/bin/sensu-api ...
    sensu    14425  0.0  3.7 104860 19292 ?        Sl   03:06   0:00 ruby /usr/bin/sensu-client ...
    sensu    14553  0.4  7.0 140544 35932 ?        Sl   03:07   0:00 ruby /usr/bin/sensu-dashboard ...

If you see an openssl error like the one below on CentOS-5, it's likely because you're on a x86_64 box but some ruby-libs or ruby-devel 1.8.5 rpm's from the base repo were accidentally installed, remove them.

    Starting sensu-client: /usr/lib/ruby/1.8/openssl/cipher.rb:22: Cipher is not a module (TypeError)
    	from /usr/lib/ruby/site_ruby/1.8/rubygems/custom_require.rb:36:in `gem_original_require'


Installing a sensu client node
==============================
Installing Sensu on a client node is similar to installing the server. We will need to install ruby, the Sensu rpm, and then configure Sensu. There are only a few small differences which are detailed below.

Install ruby 1.8.7
------------------
Follow the same steps from the `Install ruby 1.8.7` section we used to build our server.

Install sensu-client
--------------------
Follow the steps from `Install Sensu components` section we used to build our server, with the following differences:

- Only install `rubygem-sensu` and skip `rubygem-sensu-dashboard`
- You will only need the `rabbitmq` section in `/etc/sensu/config.json` file. Make sure you point it to your rabbit server.
- Only enable and start the `sensu-client` service, ie: `chkconfig sensu-client on` and `/etc/init.d/sensu-client start`.

The client will log to `/var/log/sensu/sensu-client.log`.

Add a check
==============
Now that we've installed a Sensu server and a client, let's create a simple check so we can begin to see how the pieces fit together. We're going to write a check to determine if `crond` is running. We'll be using the `check-procs.rb` script from the [sensu-community-plugins](https://github.com/sonian/sensu-community-plugins) repo.
    
Most of the plugins in the [sensu-community-plugins](https://github.com/sonian/sensu-community-plugins) repo rely on the helper classes from the sensu-plugins gem, so let's install that first. You may need to install gcc in order to build the json gem dependency. Note that we are installing this from a gem because there is not an rpm available yet.

    sudo gem install sensu-plugin --no-rdoc --no-ri

Next, we're going to grab the `check-procs.rb` script directly from github and install it into `/etc/sensu/plugins`. You don't have to install checks into this directory, but it's convenient.

    wget -O /etc/sensu/plugins/check-procs.rb https://raw.github.com/sonian/sensu-community-plugins/master/plugins/processes/check-procs.rb
    chmod 755 /etc/sensu/plugins/check-procs.rb
    
Let's create a new json file to hold our check definition in `/etc/sensu/conf.d/check_cron.json`. Put this file on both the Sensu server and client. 

(NOTE: as of sensu 0.9.2 'standalone' checks were added which only need to be configured on the client-side. We will cover standalone checks in future articles.)

    {
      "checks": {
        "cron_check": {
          "handler": "default",
          "command": "/etc/sensu/plugins/check-procs.rb -p crond -C 1 ",
          "interval": 60,
          "subscribers": [ "webservers" ]
        }
      }
    }

Next, we need to tell our client node to listen to subscribe to the `webservers` queue. The Sensu server will publish a request every 60 seconds on the `webservers` queue and any client registered to this queue will execute checks that have been registered to this queue. Edit the `/etc/sensu/conf.d/client.json` file on the client:

    {
      "client": {
        "name": "sensu-client.domain.tld",
        "address": "127.0.0.1",
        "subscriptions": [ "test", "webservers" ]
      }
    }

Finally, restart sensu on the client and server nodes.

After a few minutes we should see the following in the `/var/log/sensu/sensu-client.log` on the client:

    I, [2012-01-18T21:17:07.561000 #12984]  INFO -- : [subscribe] -- received check request -- cron_check {"message":"[subscribe] -- received check request -- cron_check","level":"info","timestamp":"2012-01-18T21:17:07.   %6N-0700"}

And on the server we should see the following in `/var/log/sensu/sensu-server.log`:

    I, [2012-01-18T21:18:07.559666 #30970]  INFO -- : [publisher] -- publishing check request -- cron_check -- webservers {"message":"[publisher] -- publishing check request -- cron_check -- webservers","level":"info","timestamp":"2012-01-18T21:18:07.   %6N-0700"}
    I, [2012-01-18T21:25:07.745012 #30970]  INFO -- : [result] -- received result -- sensu-client.domain.tld -- cron_check -- 0 -- CheckProcs OK: Found 1 matching processes; cmd /crond/
    
Next, let's see if we can raise an alert.

    /etc/init.d/crond stop

After about a minute we should see an alert on the sensu-dashboard: `http://<SERVER IP>:8080`
    
TODO-- inline insert screenshot-dashboard.png here


Add a handler
====================
Now that we have created our first check we are ready to hook it up to a handler. Out of the box Sensu ships with a 'default' handler which does nothing more than parse the JSON its fed via STDIN and spits back to STDOUT. 

There is a growing list of handlers available in the [sensu-community-plugins](https://github.com/sonian/sensu-community-plugins/tree/master/handlers) repo, including Pagerduty, IRC, Campfire, etc.
    
Let's create a simple handler that simply sends the raw check output to ourselves via email.

The most common handler type is "pipe" which tells Sensu to shell out and run the specified command. We'll cover more handler types in the future. On the server nodes, we will define our 'email' handler in `/etc/sensu/conf.d/handler_email.json`.

    {
      "handlers": {
        "email": {
          "type": "pipe",
          "command": "mail -s 'sensu alert' your@address"
        }
      }
    }

On the sensu-server and sensu-client nodes we'll also need to update our check definition and connect it to the new handler, edit the `/etc/sensu/conf.d/check_cron.json` files and modify the "handlers" attribute:

    {
      "checks": {
        "cron_check": {
          "handlers": ["default", "email"],
     ...

Restart sensu-client and sensu-server on the nodes and then stop the crond daemon again. In a few minutes we should get an email from sensu with the subject "sensu alert" and a bag full of JSON data.

This isn't the most useful handler but it illustrates the concepts of checks and handlers and how they work together. At this point we now have a working sensu-client and sensu-server to start experimenting further. In the future we'll cover more examples of checks, handlers, metrics, etc.

If you have further questions please visit #sensu on IRC Freenode.