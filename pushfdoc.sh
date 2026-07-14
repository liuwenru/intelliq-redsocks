#!/bin/bash



# 发布至fdoc上
#


tar -zcvf - --exclude='.git' ./ | pv -s $(du -sb ./ | awk '{print $1}') | ssh root@192.168.203.10 "cat > /opt/data/tmp/.liuwenru/tools/intelliq-redsocks-installer.tar.gz"
