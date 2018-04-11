# preamble #####################################################################
Name:           fdistdump-ha
Version:        0.1.1
Release:        1%{?dist}
Summary:        High availability wrapper for fdistdump

License:        GPLv3
URL:            https://github.com/CESNET/SecurityCloud
Source0:        https://raw.githubusercontent.com/CESNET/SecurityCloud/master/fdistdump/%{name}

BuildArch:      noarch

Requires:       python(abi) >= 3.4
Requires:       fdistdump-common >= 0.4.0
# the following is better, but requires newer rpm
#Requires:       (fdistdump-mpich >= 0.4.0 or fdistdump-openmpi >= 0.4.0)
Requires:       pacemaker-cli >= 1.1.16

%description
High availability wrapper for fdistdump

# install section ##############################################################
%install
install -D %{SOURCE0} %{buildroot}/%{_bindir}/%{name}

# files section ################################################################
%files
%{_bindir}/%{name}

# changelog section ############################################################
%changelog
* Wed Apr 11 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.1-1
- Change license to GPLv3
- Cleanup according to the Fedora Packaging Guidelines

* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-3
- Fix typo in Requires.

* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-2
- Fix Requires for fdistdump.

* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-1
- First vesrion of the specfile.
