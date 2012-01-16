notes
----
- setup 2 barebones centos vagrant box for writing the article (1 client, 1 server + rabbit + redis + dashboard)
- use chef ruby 1.8.7 rpm.
- use rabbitmq ssl certs



----------------

Intro
=====
In this article I will give a brief overview of a new monitoring tool called Sensu, how to install it, and then show you how to create your first Sensu check. This should lay the groundwork for future articles with more examples on how to utilize Sensu in your infrastructure.

What is Sensu?
==============
http://www.sonian.com/cloud-tools/cloud-monitoring-sensu/
I'm pretty excited about Sensu and I'd like to help others get started with it as well. After observing the frequent misconceptions and questions from new visitors to #sensu on Freenode I think perhaps the best way to do that isto  write a blog article (or two) in a tutorial style to help folks get started. If you still have questions after reading this, feel free to come by #sensu on Freenode. There are no Sensu mailing lists at this time.

Sensu is the creation of @portertech and his colleagues at sonian.com. They have graciously open-sourced the project recently and made it available to all of us searching for a modern monitoring platform (or anyone searching for an alternative to Nagios.)

Sensu is often described as the "monitoring router". Most simply put, Sensu connects "check" scripts run across many nodes with "handler" scripts. Checks are used, for example, to determine if Apache is up or down. Checks can also be used to collect metrics such as MySQL statistics. The output of checks is routed to one or more handlers. Handlers determine what to do with the results of checks. Handlers currently exist for sending alerts to Pagerduty, IRC, Twitter, etc. Handlers can also feed metrics into Graphite, Librato, etc. Writing checks and handlers is quite simple and can be done in any language.

Key points and facts:

- Ruby 1.8.7+, RabbitMQ, Redis
- Excellent test coverage (#TODO# url to travis-ci)
- Strong reliance on message-passing architecture. Messages are JSON objects.
- Re-use existing Nagios plugins
- Plugins can be written in any language
- Designed for use with modern configuration management systems such as Chef or Puppet
- Designed for cloud environments
- Lightweight, <1200 lines of code

Components
==========
Sensu is made up of several small components. I won't go into too much detail about each here, as their purpose will become obvious when we get started, so I'll just provide a few quick summaries:

sensu-server
------------
The server requests clients execute checks, receives check output and feeds to handlers. (As of version 0.9.2, clients can also execute checks that the server doesn't know about and the server will still process their results, more on this later.)

Sensu-server relies on a Redis instance to keep persistent data. It also relies heavily (as do most sensu components) on access to rabbitmq for passing data between itself and sensu-client nodes.

sensu-client
------------
Run this on all of your systems that you want to monitor. Sensu-client will execute checks scripts (think `check_http`, `check_load`, etc) and return the results to sensu-server via rabbitmq.

sensu-api
------------
A REST API that provides access to various pieces of data maintained on the sensu-server in Redis. You will typically run this on the same server as your sensu-server or Redis instance. It is mostly used by internal sensu components at this time, so we probably won't cover it much more in this article.

sensu-dashboard
---------------
A simple web GUI that shows the current state of your sensu checks and allows you to perform actions like temporarily silencing specific checks or nodes.

Installing
==========
As you start to explore Sensu you will find that it was built from the start to be used in conjunction with a CM tool such as Chef or Puppet. However, for the purposes of this article I will walk through a simple manual install and config. 

You will probably want to use Sensu with Chef or Puppet really soon after you get bootstrapped (of course you're already using a modern CM tool in your infrastructure anyway, right?) There are good Chef (#TODO# url) and Puppet (#TODO# url) recipes in the github repos that can help you get going fairly quickly. There are also a few community members working on improving these pieces so should get even better over time.

Additionally, the original dev platform for Sensu was Ubuntu but work has been done to help make it a little more CentOS/RHEL-friendly. I'm going to use CentOS-5 in this article just because I'm more familiar with this platform than the debian/ubuntu family. In any case, it shouldn't matter too much because the purpose of this article is to show you Sensu.

We will use 2 nodes, one will be our server and the other will just be a simple client (perhaps it's your web server). To get started we'll need to install the following:

Install sensu server
====================

install ruby 1.8.7
------------------
Sensu needs ruby 1.8.7+ but CentOS-5 ships with an old Ruby 1.8.5. We will use the ruby 1.8.7 rpm's from Opscode's Chef. See here for additional details: http://wiki.opscode.com/display/chef/Installing+Chef+Client+on+CentOS#InstallingChefClientonCentOS-InstallRuby

    sudo wget -O /etc/yum.repos.d/aegisco.repo http://rpm.aegisco.com/aegisco/el5/aegisco.repo
    sudo yum install ruby ruby-devel ruby-ri ruby-rdoc ruby-shadow rubygems curl

install rabbitmq
----------------
We will use the rabbit install guide from here as a reference: http://www.rabbitmq.com/install-rpm.html

The EPEL-5 yum repo contains the older R12B version of Erlang which would work fine ok with rabbit except we wouldn't have access to some of the nice management plugins nor SSL. Thus, we'll be installing a newer Erlang from the `epel-erlang` repo. We still need the EPEL-5 repo for some dependencies so we will install both repos.

    sudo rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm
    sudo wget -O /etc/yum.repos.d/epel-erlang.repo http://repos.fedorapeople.org/repos/peter/erlang/epel-erlang.repo
    sudo yum install erlang
    
Install RabbitMQ

    sudo rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
    sudo rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/v2.7.1/rabbitmq-server-2.7.1-1.noarch.rpm

We need to make some SSL certs for our rabbitmq server and the sensu clients. I put a simple script up on github (#TODO# url) to help with this. It's fairly simple and you'll want to change a few things in the `openssl.cnf` to tweak to your organization if you use this in production. The script will generate a few files that we'll need throughout the guide, so keep them nearby.

    sudo yum install git
    git clone git://github.com/joemiller/joemiller.me-intro-to-sensu.git
    cd joemiller.me-intro-to-sensu/
    ./ssl_certs.sh clean
    ./ssl_certs.sh generate

Configure RabbitMQ to use these SSL certs

    mkdir /etc/rabbitmq/ssl
    cp server_key.pem /etc/rabbitmq/ssl/
    cp server_cert.pem /etc/rabbitmq/ssl/
    cp testca/cacert.pem /etc/rabbitmq/ssl/
    
Create file `/etc/rabbitmq/rabbitmq.conf` with contents:

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

Verify operation with the RabbitMQ Web UI: Username is "guest", password is "guest" - http://<IP ADDRESS>:55672. Protocol amqp should be bound to port 5672 and amqp/ssl on port 5671.

Finally, let's create a `sensu` vhost and a `sensu` user/password on our rabbit:

    rabbitmqctl add_vhost /sensu
    rabbitmqctl add_user sensu mypass
    rabbitmqctl set_permissions -p /sensu sensu ".*" ".*" ".*"

install redis
-------------
At this point we already have the EPEL-5 repo installed on our server so we will install EPEL's version of Redis, even though it is fairly old at v2.0.

    sudo yum install redis
    sudo /sbin/chkconfig redis on
    sudo /etc/init.d/redis start

install sensu-server, sensu-client, sensu-api
---------------------------------------------
Now we are ready to install Sensu. The rpm installs sensu-server, sensu-client, and sensu-api. On our server we will use all 3 but our clients will only use sensu-client. Sensu-dashboard is installed separately.

We are going to use @jeremy_carroll's (#TODO# url to twitter) recently created yum repo to install sensu via rpm. This repo contains sensu rpm's for both CentOS 5 and 6 (and RHEL5/6). It's awesome that Jeremy has taken the time to set this up and I hope we can use this as a basis for automating the building of rpms and debs for all releases of Sensu. Since this repo was setup pretty much as this blog was being written, it's possible that this repo will move to a different location in the future.

    sudo rpm -Uvh http://yum.carrollops.com/el/5/sensu-release-6-1.noarch.rpm

We need to ignore the rubygem rpm's that come from EPEL because they will conflict with the sensu rpm's. Edit your `/etc/yum.repos.d/epel.repo` file and add the following line to the [epel] section.

    exclude=rubygem*

Install:

    sudo yum install rubygem-sensu
    sudo chkconfig --add sensu-server
    sudo chkconfig --add sensu-api
    sudo chkconfig --add sensu-client

Copy SSL client key + cert that we created earlier into `/etc/sensu/ssl`

    cp client_key.pem client_cert.pem  /etc/sensu/ssl/

Next we need to configure sensu. For now we will create just enough config to start sensu. Later we will add checks and handlers. Sensu reads its config out of `/etc/sensu/config.json` by default and any files you place into the `/etc/sensu/conf.d` directory. Create `/etc/sensu/config.json`:

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
      "rabbitmq": {
        "host": "localhost",
        "port": 5672,
        "user": "sensu",
        "password": "sensu",
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

Let's try to start the components:

    sudo /etc/init.d/sensu-server start
    sudo /etc/init.d/sensu-api start
    sudo /etc/init.d/sensu-client start    

#TODO# get this stuff working

install sensu-dashboard
-----------------------
#TODO# install dashboard, configure it, set it to startup, start it, etc


installing a sensu client node
==============================

- install ruby 1.8.7
- install sensu



Writing first check
===================
- ...

Writing first handler
=====================
- ...