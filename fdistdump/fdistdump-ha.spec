# preamble #####################################################################
Name:           fdistdump-ha
Version:        0.1.0
Release:        3%{?dist}
Summary:        High availability wrapper for fdistdump

License:        BSD
URL:            https://github.com/CESNET/SecurityCloud
Source0:        https://raw.githubusercontent.com/CESNET/SecurityCloud/master/fdistdump/%{name}

Group:          Applications/Databases
Vendor:         CESNET, a.l.e.
Packager:       Jan Wrona <wrona@cesnet.cz>

BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
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
rm -rf $RPM_BUILD_ROOT
mkdir -p %{buildroot}%{_bindir}
install %{SOURCE0} %{buildroot}%{_bindir}

# clean section ################################################################
%clean
rm -rf $RPM_BUILD_ROOT

# files section ################################################################
%files
%{_bindir}/%{name}

# changelog section ############################################################
%changelog
* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-3
- Fix typo in Requires.

* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-2
- Fix Requires for fdistdump.

* Thu Mar 22 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-1
- First vesrion of the specfile.
