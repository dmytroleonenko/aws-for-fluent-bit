echo -n "AWS for Fluent Bit Container Image Version "
cat /AWS_FOR_FLUENT_BIT_VERSION
exec /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf
