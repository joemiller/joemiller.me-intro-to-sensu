#!/bin/sh
function clean {
rm -f ./server_*
rm -f ./client_*
rm -f ./testca/cacert*
rm -f ./testca/index.txt.*
rm -f ./testca/private/*
rm -f ./testca/serial.old
rm -f ./testca/certs/*
rm -f ./testca/index.txt
rm -f ./testca/serial
}

function generate {
mkdir -p testca/private
mkdir -p testca/certs
touch testca/index.txt
echo 01 > testca/serial
cd testca
openssl req -x509 -config ../openssl.cnf -newkey rsa:2048 -days 40000 -out cacert.pem -outform PEM -subj /CN=TestCA/ -nodes
openssl x509 -in cacert.pem -out cacert.cer -outform DER
cd ..
openssl genrsa -out server_key.pem 2048
openssl req -new -key server_key.pem -out server_req.pem -outform PEM -subj /CN=$(hostname)/O=server/ -nodes
cd testca
openssl ca -config ../openssl.cnf -in ../server_req.pem -out ../server_cert.pem -notext -batch -extensions server_ca_extensions
cd ..
openssl pkcs12 -export -out server_keycert.p12 -in server_cert.pem -inkey server_key.pem -passout pass:DemoPass
openssl genrsa -out client_key.pem 2048
openssl req -new -key client_key.pem -out client_req.pem -outform PEM -subj /CN=$(hostname)/O=client/ -nodes
cd testca
openssl ca -config ../openssl.cnf -in ../client_req.pem -out ../client_cert.pem -notext -batch -extensions client_ca_extensions
cd ..
openssl pkcs12 -export -out client_keycert.p12 -in client_cert.pem -inkey client_key.pem -passout pass:DemoPass

}

if [ "$1" = "generate" ]; then 
  echo "Generating ssl certificates..."
  generate
  exit
elif [ "$1" = "clean" ]; then
  echo "Cleaning up previously generated certificates..."
  clean
else
  echo "You must run the script with either generate or clean, e.g. ./ssl_certs.sh generate"
fi
