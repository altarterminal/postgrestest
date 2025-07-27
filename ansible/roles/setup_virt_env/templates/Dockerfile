FROM ubuntu:22.04

ARG user_name="{{ user_name }}"
ARG user_id="{{ user_id }}"
ARG proxy_setting="{{ proxy_setting }}"

# settings for proxy
RUN if [ -n "${proxy_setting}" ]; then echo 'Acquire::http::Proxy  "http://'"${proxy_setting}"'";' >> '/etc/apt/apt.conf'; fi
RUN if [ -n "${proxy_setting}" ]; then echo 'Acquire::https::Proxy "http://'"${proxy_setting}"'";' >> '/etc/apt/apt.conf'; fi

# settings for packages
RUN apt update && apt upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata
RUN apt install -y sudo locales bash-completion openssh-server net-tools iputils-ping python3-pip vim

# settings for timezone
RUN ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

# settings for user
RUN useradd -u ${user_id} -m -d /home/${user_name} -G sudo ${user_name}
RUN echo "${user_name}:${user_name}" | chpasswd
RUN chsh -s /bin/bash ${user_name}
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN chown -R ${user_name} /home/${user_name}

# settings for sshd
RUN mkdir /var/run/sshd
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/'  /etc/ssh/sshd_config
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/'      /etc/ssh/sshd_config

# settings for ssh
RUN mkdir /home/${user_name}/.ssh
COPY id_rsa.pub /home/${user_name}/.ssh/authorized_keys
RUN chmod 600 /home/${user_name}/.ssh/authorized_keys
RUN chown ${user_name}:${user_name} /home/${user_name}/.ssh/authorized_keys

CMD ["/usr/sbin/sshd", "-D"]
