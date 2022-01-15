FROM ubuntu:20.04
MAINTAINER David Villavicencio

# OS updates and install
RUN apt-get -qq update
RUN apt-get install git curl clang gcc python3 sudo zsh -qq -y

# Create test user and add to sudoers
RUN useradd -m -s /bin/zsh tester
RUN usermod -aG sudo tester
RUN echo "tester   ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers

# Add dotfiles and chown
ADD . /home/tester/projects/dotfiles
RUN chown -R tester:tester /home/tester

# Switch testuser
USER tester
ENV HOME /home/tester

# Install Brew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 

# Change working directory
WORKDIR /home/tester/projects/dotfiles

CMD [ "zsh" ]
