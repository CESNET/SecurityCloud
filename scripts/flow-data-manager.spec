# preamble #####################################################################
Name:           flow-data-manager
Version:        0.1.0
Release:        1%{?dist}
Summary:        Flow file data manager, part of the SecurityCloud toolset

License:        BSD
URL:            https://github.com/CESNET/SecurityCloud
Source0:        https://raw.githubusercontent.com/CESNET/SecurityCloud/master/scripts/%{name}

Group:          Applications/Databases
Vendor:         CESNET, a.l.e.
Packager:       Jan Wrona <wrona@cesnet.cz>

BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

Requires:       python(abi) >= 3.4

%description
Flow file data manager, part of the SecurityCloud toolset.

# install section ##############################################################
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p %{buildroot}%{_bindir}
install %{_sourcedir}/%{name} %{buildroot}%{_bindir}

# clean section ################################################################
%clean
rm -rf $RPM_BUILD_ROOT

# files section ################################################################
%files
%{_bindir}/%{name}

# changelog section ############################################################
%changelog
* Wed Jan 31 2018 Jan Wrona <wrona@cesnet.cz> - 0.1.0-1
- First vesrion of the specfile.
