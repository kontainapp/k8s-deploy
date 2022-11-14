#!/bin/bash

# Copyright 2022 Kontain
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[ "$TRACE" ] && set -x

for arg in "$@"
do
   case "$arg" in
        --dir=*)
            output_dir="${1#*=}"
        ;;
        --nginx-config)
            nginx_config=yes
        ;;
        --process=*)
            process_dir="${1#*=}"
        ;;
    esac
    shift
done

# declare -a ip_array=($(kubectl get service | grep sb- | awk -e '{print $3}'))
declare -a ip_array=($(kubectl get pod -o wide  | awk -e '/sb-/{print $(NF - 3)}'))

total=${#ip_array[@]}

rm -f forward.conf

for (( i=0; i<$total; i++ ))
do

    config_str="
    location /$i {
        rewrite ^/$i(.*) /\$1 break;
        proxy_pass http://${ip_array[$i]}:8080 ;
    }
"
    echo "$config_str" >> forward.conf
done

sudo cp forward.conf /etc/nginx/default.d/
sudo systemctl restart nginx

rm -f forward.conf

# run tests
# rate_start=10
# rate_end=70
# for (( r=$rate_start; r<=$rate_end; r++ ))
#     wrk -c2 -t2 -d30 -L -s setup.lua -R${r}0 http://localhost > out_$r.txt
# do
