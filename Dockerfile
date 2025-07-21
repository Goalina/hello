FROM local_discourse/web_only:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 设置目录权限
RUN mkdir -p /shared/state/logrotate && ln -s /shared/state/logrotate /var/lib/logrotate && \
    mkdir -p /shared/state/anacron-spool && ln -s /shared/state/anacron-spool /var/spool/anacron && \
    mkdir -p /shared/uploads && mkdir -p /shared/backups && \
    rm -rf /shared/tmp/{backups,restores} && mkdir -p /shared/tmp/{backups,restores}

RUN rm /etc/apt/trusted.gpg && \
    curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/yarn.gpg && \
    apt-get update

RUN DEBIAN_FRONTEND=noninteractive apt purge -y postgresql-client-15 && \
    DEBIAN_FRONTEND=noninteractive apt autoremove -y && \
    DEBIAN_FRONTEND=noninteractive apt install -y postgresql-client-16 && \
    pg_dump --version

# 参考 00-fix-var-logs 文件修改用户权限
RUN rm -f /etc/runit/1.d/00-fix-var-logs && \
    mkdir -p /var/log/nginx && \
    chown -R discourse:discourse /var/log/nginx && \
    chmod -R 644 /var/log/nginx && \
    chmod -R 755 /var/log/nginx && \
    touch /var/log/syslog   && chown -f discourse:discourse /var/log/syslog* && \
    touch /var/log/auth.log && chown -f discourse:discourse /var/log/auth.log* && \
    touch /var/log/kern.log && chown -f discourse:discourse /var/log/kern.log*

# 参考 /etc/service/rsyslog 脚本内容
RUN rm -rf /etc/service/rsyslog
# 容器通过 cron， 使 cron 成为容器的 主进程（PID 1），能直接接收系统信号（如 SIGTERM）；不需要该功能
# seteuid: Operation not permitted
RUN rm -rf /etc/service/cron 

# 参考 /etc/service/unicorn/run, 适配切普通用户的修改
RUN mkdir -p /shared/log/rails && \
    chown -R discourse:discourse /shared/log/rails
COPY ./discourse_config/run /etc/service/unicorn/run
COPY ./discourse_config/discourse /usr/local/bin/discourse
COPY ./discourse_config/00-ensure-links /etc/runit/1.d/00-ensure-links
RUN chmod +x /etc/service/unicorn/run && \
    chmod +x /etc/runit/1.d/00-ensure-links && \
    chmod +x /usr/local/bin/discourse

# 修改 nginx 的启动脚本，适配切换到普通用户的修改
RUN sed -i "s|user www-data;|# user discourse;|g" /etc/nginx/nginx.conf

# 禁用 TLSv1 和 TLSv1.1，仅保留 TLSv1.2+TLSv1.3
RUN sed -i 's|ssl_protocols .*|ssl_protocols TLSv1.2 TLSv1.3;|' /etc/nginx/nginx.conf && \
    sed -i 's|ssl_protocols .*|ssl_protocols TLSv1.2 TLSv1.3;|' /etc/nginx/conf.d/discourse.conf

# 修改 discourse 用户shell的umask配置和历史记录设置
RUN echo "umask 0027" >> /home/discourse/.bashrc && \
    echo "set +o history" >> /home/discourse/.bashrc && \
    sed -i "s|HISTSIZE=1000|HISTSIZE=0|" /home/discourse/.bashrc && \
    source /home/discourse/.bashrc

# 限制 discourse 用户的密码有效期
RUN chage --maxdays 30 discourse && \
    passwd -l discourse && \
    usermod -s /sbin/nologin sync

WORKDIR /var/www/discourse
COPY ./discourse_config/rails /usr/local/bin/rails

# 忽略全零 IP
RUN sed -i "/def get(ip)/a \\    return nil if ip == '0.0.0.0'  # ignore all-zero IP" \
    /var/www/discourse/lib/discourse_ip_info.rb

# 修改权限
RUN chown -R discourse:discourse /etc/runit/1.d && \
    chown -R discourse:discourse /etc/service && \
    chmod -R 755 /etc/service && \
    chown -R discourse:discourse /var/www/discourse && \
    chown -R discourse:discourse /shared && \
    chown -R discourse:discourse /var/log && \
    chown -R discourse:discourse /var/lib && \
    chown -R discourse:discourse /var/run && \
    chown -R discourse:discourse /run && \
    chown -R discourse:discourse /tmp && \
    chown -R discourse:discourse /dev && \
    chown -R discourse:discourse /var/spool && \
    chown -R discourse:discourse /etc/ssl

# 降权 /var 下关键目录
RUN chown -R discourse:discourse /var/backups /var/local /var/mail /var/nginx /var/www && \
    find /var/backups -type d -exec chmod 750 {} \; && \
    find /var/backups -type f -exec chmod 640 {} \; && \
    find /var/local -type d -exec chmod 750 {} \; && \
    find /var/local -type f -exec chmod 640 {} \; && \
    find /var/mail -type d -exec chmod 750 {} \; && \
    find /var/mail -type f -exec chmod 640 {} \; && \
    find /var/nginx -type d -exec chmod 750 {} \; && \
    find /var/nginx -type f -exec chmod 640 {} \; && \
    find /var/www -type d -exec chmod 750 {} \; && \
    find /var/www -type f -executable -exec chmod 750 {} \; && \
    find /var/www -type f ! -executable -exec chmod 640 {} \;


# 处理 /etc/nginx 的所有者及权限
RUN chown -R discourse:discourse /etc/nginx && \
    find /etc/nginx -type d   -exec chmod 750 {} \; && \
    find /etc/nginx -type f -perm -u=w -exec chmod 640 {} \; && \
    find /etc/nginx -type f ! -perm -u=w -exec chmod 400 {} \; 

# 目录权限收紧
RUN chown -R discourse:discourse /var/www/discourse && \
    find /var/www/discourse -type d   -exec chmod 750 {} \; && \
    find /var/www/discourse -type f -executable -exec chmod 750 {} \; && \
    find /var/www/discourse -type f ! -executable -exec chmod 640 {} \;

# 目录权限收紧
RUN chown -R discourse:discourse /home/discourse && \
    chmod 750 /home/discourse && \
    find /home/discourse -type d -exec chmod 750 {} \; && \
    find /home/discourse -type f -exec chmod 640 {} \;

# remove sudo
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive SUDO_FORCE_REMOVE=yes apt-get purge -y sudo && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# 卸载所有构建/调试工具
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
    build-essential \
    cmake \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    flex \
    mcpp \
    gcc \
    g++ \
    cpp \
    binutils \
    gdb \
    strace \
    ltrace \
    tcpdump \
    nmap \
    netcat-openbsd \
    wireshark-common \
    wireshark \
    rpcbind && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# 切换到非root用户
USER discourse

RUN . /home/discourse/.bashrc

# 保留原有的ENTRYPOINT和CMD
# ENTRYPOINT ["sh", "-c", "rails db:migrate && /sbin/boot"]
