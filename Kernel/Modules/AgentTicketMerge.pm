# --
# Kernel/Modules/AgentTicketMerge.pm - to merge tickets
# Copyright (C) 2001-2005 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: AgentTicketMerge.pm,v 1.4 2005-07-23 08:57:22 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::Modules::AgentTicketMerge;

use strict;
use Kernel::System::CustomerUser;

use vars qw($VERSION);
$VERSION = '$Revision: 1.4 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;

    # allocate new hash for object
    my $Self = {};
    bless ($Self, $Type);

    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }

    # check needed Opjects
    foreach (qw(ParamObject DBObject TicketObject LayoutObject LogObject
                 QueueObject ConfigObject)) {
        die "Got no $_!" if (!$Self->{$_});
    }

    $Self->{CustomerUserObject} = Kernel::System::CustomerUser->new(%Param);

    return $Self;
}
# --
sub Run {
    my $Self = shift;
    my %Param = @_;
    my $Output;
    # check needed stuff
    if (!$Self->{TicketID}) {
        # error page
        return $Self->{LayoutObject}->ErrorScreen(
            Message => "Need TicketID is given!",
            Comment => 'Please contact the admin.',
        );
        return $Output;
    }
    # check permissions
    if (!$Self->{TicketObject}->Permission(
        Type => 'rw',
        TicketID => $Self->{TicketID},
        UserID => $Self->{UserID})) {
        # error screen, don't show ticket
        return $Self->{LayoutObject}->NoPermission(WithHeader => 'yes');
    }

    # merge action
    if ($Self->{Subaction} eq 'Merge') {
        my $Tn = $Self->{TicketObject}->TicketNumberLookup(TicketID => $Self->{TicketID});
        my $MainTicketNumber = $Self->{ParamObject}->GetParam(Param => 'MainTicketNumber');
        my $MainTicketID = $Self->{TicketObject}->TicketIDLookup(TicketNumber => $MainTicketNumber);
        # check permissions
        if (!$Self->{TicketObject}->Permission(
            Type => 'rw',
            TicketID => $MainTicketID,
            UserID => $Self->{UserID})) {
            # error screen, don't show ticket
            return $Self->{LayoutObject}->NoPermission(WithHeader => 'yes');
        }
        # check errors
        if ($Self->{TicketID} == $MainTicketID || !$Self->{TicketObject}->TicketMerge(MainTicketID => $MainTicketID, MergeTicketID => $Self->{TicketID}, UserID => $Self->{UserID})) {
            my %Ticket = $Self->{TicketObject}->TicketGet(TicketID => $Self->{TicketID});
            my $Output = $Self->{LayoutObject}->Header();
            $Output .= $Self->{LayoutObject}->NavigationBar();
            $Output .= $Self->{LayoutObject}->Output(TemplateFile => 'AgentTicketMerge', Data => {%Param,%Ticket});

            $Output .= $Self->{LayoutObject}->Footer();
            return $Output;
        }
        else {
            # --
            # get params
            # --
            foreach (qw(From To Subject Body InformSender)) {
                $Param{$_} = $Self->{ParamObject}->GetParam(Param => $_) || '';
            }
            # --
            # check forward email address
            # --
            foreach my $Email (Mail::Address->parse($Param{BounceTo})) {
                my $Address = $Email->address();
                if ($Self->{SystemAddress}->SystemAddressIsLocalAddress(Address => $Address)) {
                    # error page
                    return $Self->{LayoutObject}->ErrorScreen(
                        Message => "Can't forward ticket to $Address! It's a local ".
                          "address! You need to move it!",
                        Comment => 'Please contact the admin.',
                    );
                }
            }
            # --
            # send customer info?
            # --
            if ($Param{InformSender}) {
                my %Ticket = $Self->{TicketObject}->TicketGet(TicketID => $Self->{TicketID});
                $Param{Body} =~ s/<OTRS_TICKET>/$Ticket{TicketNumber}/g;
                $Param{Body} =~ s/<OTRS_MERGE_TO_TICKET>/$MainTicketNumber/g;
                if (my $ArticleID = $Self->{TicketObject}->ArticleSend(
                  ArticleType => 'email-external',
                  SenderType => 'agent',
                  TicketID => $Self->{TicketID},
                  HistoryType => 'SendAnswer',
                  HistoryComment => "Merge info to '$Param{To}'.",
                  From => $Param{From},
                  Email => $Param{Email},
                  To => $Param{To},
                  Subject => $Param{Subject},
                  UserID => $Self->{UserID},
                  Body => $Param{Body},
                  Type => 'text/plain',
                  Charset => $Self->{LayoutObject}->{UserCharset},
                )) {
                  ###
                }
                else {
                    # error page
                    return $Self->{LayoutObject}->ErrorScreen();
                }
            }
            # redirect
            return $Self->{LayoutObject}->Redirect(OP => $Self->{LastScreenOverview});
        }
    }
    else {
        # merge box
        my %Ticket = $Self->{TicketObject}->TicketGet(TicketID => $Self->{TicketID});
        my $Output = $Self->{LayoutObject}->Header(Value => $Ticket{TicketNumber});
        $Output .= $Self->{LayoutObject}->NavigationBar();
        # get lock state && write (lock) permissions
        if (!$Self->{TicketObject}->LockIsTicketLocked(TicketID => $Self->{TicketID})) {
            # set owner
            $Self->{TicketObject}->OwnerSet(
                TicketID => $Self->{TicketID},
                UserID => $Self->{UserID},
                NewUserID => $Self->{UserID},
            );
            # set lock
            if ($Self->{TicketObject}->LockSet(
                TicketID => $Self->{TicketID},
                Lock => 'lock',
                UserID => $Self->{UserID}
            )) {
                # show lock state
                $Output .= $Self->{LayoutObject}->TicketLocked(TicketID => $Self->{TicketID});
            }
        }
        else {
            my ($OwnerID, $OwnerLogin) = $Self->{TicketObject}->OwnerCheck(
                TicketID => $Self->{TicketID},
            );
            if ($OwnerID != $Self->{UserID}) {
                $Output .= $Self->{LayoutObject}->Warning(
                    Message => "Sorry, the current owner is $OwnerLogin!",
                    Comment => 'Please change the owner first.',
                );
               $Output .= $Self->{LayoutObject}->Footer();
               return $Output;
            }
        }
        my %Article = $Self->{TicketObject}->ArticleLastCustomerArticle(
            TicketID => $Self->{TicketID},
        );
        # --
        # prepare subject ...
        # --
        # get customer data
        my %Customer = ();
        if ($Ticket{CustomerUserID}) {
            %Customer = $Self->{CustomerUserObject}->CustomerUserDataGet(
                User => $Ticket{CustomerUserID},
            );
        }
        $Article{Subject} = $Self->{TicketObject}->TicketSubjectBuild(
            TicketNumber => $Ticket{TicketNumber},
            Subject => $Article{Subject} || '',
        );
        # --
        # prepare from ...
        # --
        my %Address = $Self->{QueueObject}->GetSystemAddress(
            QueueID => $Ticket{QueueID},
        );
        $Article{QueueFrom} = "$Address{RealName} <$Address{Email}>";
        $Article{Email} = $Address{Email};
        $Article{RealName} = $Address{RealName};
        # prepare salutation
        $Param{Salutation} = $Self->{QueueObject}->GetSalutation(%Article);
        # prepare signature
        $Param{Signature} = $Self->{QueueObject}->GetSignature(%Article);
        foreach (qw(Signature Salutation)) {
            # get and prepare realname
            if ($Param{$_} =~ /<OTRS_CUSTOMER_REALNAME>/) {
                my $From = '';
                if ($Ticket{CustomerUserID}) {
                    $From = $Self->{CustomerUserObject}->CustomerName(UserLogin => $Ticket{CustomerUserID});
                }
                if (!$From) {
                    $From = $Article{From} || '';
                    $From =~ s/<.*>|\(.*\)|\"|;|,//g;
                    $From =~ s/( $)|(  $)//g;
                }
                $Param{$_} =~ s/<OTRS_CUSTOMER_REALNAME>/$From/g;
            }
            # replace other needed stuff
            $Param{$_} =~ s/<OTRS_FIRST_NAME>/$Self->{UserFirstname}/g;
            $Param{$_} =~ s/<OTRS_LAST_NAME>/$Self->{UserLastname}/g;
            $Param{$_} =~ s/<OTRS_USER_ID>/$Self->{UserID}/g;
            $Param{$_} =~ s/<OTRS_USER_LOGIN>/$Self->{UserLogin}/g;
            # replace ticket data
            foreach my $TicketKey (keys %Ticket) {
                if ($Ticket{$TicketKey}) {
                    $Param{$_} =~ s/<OTRS_TICKET_$TicketKey>/$Ticket{$TicketKey}/gi;
                }
            }
            # cleanup all not needed <OTRS_TICKET_ tags
            $Param{$_} =~ s/<OTRS_TICKET_.+?>/-/gi;
            # replace customer data
            foreach my $CustomerKey (keys %Customer) {
                if ($Customer{$CustomerKey}) {
                    $Param{$_} =~ s/<OTRS_CUSTOMER_$CustomerKey>/$Customer{$CustomerKey}/gi;
                }
            }
            # cleanup all not needed <OTRS_CUSTOMER_ tags
            $Param{$_} =~ s/<OTRS_CUSTOMER_.+?>/-/gi;
            # replace config options
            $Param{$_} =~ s{<OTRS_CONFIG_(.+?)>}{$Self->{ConfigObject}->Get($1)}egx;
        }
        $Output .= $Self->{LayoutObject}->Output(TemplateFile => 'AgentTicketMerge', Data => {%Param,%Ticket, %Article});
        $Output .= $Self->{LayoutObject}->Footer();
        return $Output;
    }
}
# --
1;
