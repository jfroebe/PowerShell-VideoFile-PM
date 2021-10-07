###################################################################
# Class VideoFile - Jason Froebe
###################################################################

## USAGE
## at top of script importing VideFile.psm1:
## using module VideoFile 
##
## use within your script:
## [VideoFile] $myVideoFile =  [VideoFile]::new($FileName)
##
## Works with PS 5 and higher (even ps core on Linux)

class VideoFile {
    # Properties
    [bool]      $IsVideoFile    = 0
    [hashtable] $Format         = @{}
    [hashtable] $Streams        = @{}
    [hashtable] $Tags           = @{}
    [int64]     $size           = 0

    # Hidden Properties
    hidden [String] $_FileName
    hidden [String] $_Ffprobe_location

    #---------------
    # Constructors
    #---------------
    VideoFile () {
        $this._AddProperty_FileName()
    }

    # Constructor with file name
    VideoFile ([String] $FileName) {
        $this._AddProperty_FileName()
        $this.FileName = $FileName
    }

    #---------------
    # Add Properties
    #---------------
    hidden [void] _AddProperty_FileName () {
        # Getter / Setters & Powershell v5 classes:
        #   https://stackoverflow.com/questions/40977472/is-it-possible-to-override-the-getter-setter-functions-in-a-powershell-5-class

        $this | Add-Member -Name FileName -MemberType ScriptProperty -Value {
            # This is the getter
            return $this._FileName
        } -SecondValue {
            param($value)

            # This is the setter
            if (Test-Path -LiteralPath $value -PathType Leaf) {
                $this._FileName = $value
                $this._populateVideometadata()
            } else {
                Write-Error -Message "File Not Found: $value"
                throw [System.IO.FileNotFoundException] "$value not found."
            }
        }
    }

    #---------------
    # Do things
    #---------------
    hidden [void] _populateVideometadata () {
        if ( $null -eq $this.Ffprobe_location ) {
                $this._Ffprobe_location = ( Get-Command 'ffprobe' ).Source
        }

        if ( $null -eq $this._Ffprobe_location -or $this._Ffprobe_location -eq '' ) {
            # error message
            Write-Error -Message "Unable to locate ffprobe Make sure it is in your PATH" -Category InvalidResult
            Write-Host "Unable to locate ffprobe.exe  Make sure it is in your PATH" -ForegroundColor White -BackgroundColor Red
            return
        } else {
            [String] $filename = $this.FileName
            [String] $ArgumentList = ' -v quiet -show_format -show_streams -print_format json -i "{0}"' -f $filename
            [String] $cmd = $this._Ffprobe_location + $ArgumentList

            Try {
                [String] $cmd_output = Invoke-Expression $cmd
            } Catch {
                [String] $ErrorMessage = $_.Exception.Message
                [String] $FailedItem = $_.Exception.ItemName

                Write-Error -Message "FFProbe didn't work as expected: $FailedItem : $ErrorMessage" -Category InvalidResult
                Write-Host "INVALID RESULT: No output received from ffprobe: $FailedItem : $ErrorMessage" -ForegroundColor White -BackgroundColor Red

                return
            }

            if ( $Null -eq $cmd_output -or $cmd_output.Length -eq 0 ) {
                Write-Error -Message "No output received from ffprobe: $cmd" -Category InvalidResult
                Write-Host "INVALID RESULT: No output received from ffprobe: $cmd" -ForegroundColor White -BackgroundColor Red
                return
            } else {
                [PSObject] $tmp_MetaData = $cmd_output | ConvertFrom-Json

                # Populate File format information
                $this.Format.Name       = $tmp_MetaData.Format.format_name
                $this.Format.LongName   = $tmp_MetaData.Format.format_long_name
                $this.Format.StartTime  = $tmp_MetaData.Format.start_time
                $this.Format.Duration   = $tmp_MetaData.Format.duration

                # File Size
                $this.Size              = $tmp_MetaData.Format.size

                # Tags - Tags are stored as a PSObject but we want to make it a HashTable
                # $this.Tags              = $tmp_MetaData.Format.tags[0]
                $tmp_MetaData.Format.tags | Get-Member -MemberType NoteProperty | ForEach-Object {
                    $this.Tags.($_.name) = $tmp_MetaData.Format.tags.($_.name)
                }

                # Populate stream information
                $this.Streams.Count     = $tmp_MetaData.format.nb_streams
                $this.Streams.Audio     = $tmp_MetaData.Streams | Where-Object { $_.codec_type -eq 'audio' }
                $this.Streams.Video     = $tmp_MetaData.Streams | Where-Object { $_.codec_type -eq 'video' }
                $this.Streams.Subtitle  = $tmp_MetaData.Streams | Where-Object { $_.codec_type -eq 'subtitle' }
                $this.Streams.Other     = $tmp_MetaData.Streams | Where-Object { $_.codec_type -notin ('audio', 'video', 'subtitle') }
                
                if ($Null -ne $this.Streams.Video) {
                    # Mark the file as being a video file
                    $this.IsVideoFile = 1
                }
            }
        }
    }
}
