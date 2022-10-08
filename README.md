## ConvertIm3
The ConvertIm3 executable was written by Richard Wilton to extract\ inject the bitmap and metadata information from the akoya im3 image files. ConvertIm3Path is a powershell code, added by Benjamin Green, and is a soft wrapper for the executable to run on the sample level, with optional inputs and exports. Both codes are dependent on the images being in the AstropathPipeline directory format which is slightly different than the standard Akoya imagery directory format. ConvertIm3Cohort.ps1 is a wrapper for ConvertIm3Path.ps1 which runs through all specimens in a directory, the cohort is hard coded at present and should be modified in the code. All parameters for the ps1 codes are described in the code body, the Usage.txt is for CovertIm3.exe. 

## ConvertIm3
The ConvertIM3 application reads and writes AKOYA IM3 ("image cube") files.

ConvertIM3 uses a simple set of C# classes to represent the contents of an IM3 file. Unfortunately, the IM3 format is undocumented. There are no software tools available that manage IM3 files directly.  It is more practical to transform IM3 into a well-known format that can be handled by generally-available software.  Since the IM3 format is essentially a hierarchy of self-described groups of data, a straightforward way to work with IM3 is to convert it to and from XML.

ConvertIM3 can carry out the following operations:
- convert IM3 to XML
- convert XML to IM3
- extract one IM3 data field (that is, one XML element) from IM3-formatted data
- replace the contents of one IM3 data field (that is, one XML element) in IM3-formatted data

Command-line syntax:

 ```
 ConvertIM3 <input_file_specification> IM3|XML|DAT
            [/o <output_directory_path>]
            [/t <max_XML_data_length>] 
            [/x <XPath_expression>]
            [/i <injected_data_file_specification>]
``` 

Extended directions can be found [here](./ConvertIM3Usage.txt).

## ConvertIm3Path & ConvertIm3Cohort
ConvertIm3Path & ConvertIm3Cohort are soft wrappers written in powershell for the executable to run *ConvertIm3* on the ```<SlideID>``` level for specific output desired by the *AstroPathPipeline*, with optional inputs and exports. Both codes are dependent on the images being in the aforementioned [directory structure](../../hpfs/imagecorrection/docs/ImportantDefinitions.md#5731-image-correction-expected-directory-structure "Title"). ConvertIm3Cohort.ps1 is actually just a wrapper for ConvertIm3Path.ps1 which runs through all specimens in a directory, the cohort location is hard coded at present and should be modified in the code. 
 
Usage: 
- To "shred" a directory of im3s use:
  - ```ConvertIm3Path -<base> -<FWpath> -<SlideID> -s [-a -d -xml]```
  - Optional arguements:
	  - ```-d```: only extract the binary bitmap for each image into the output directory
	  - ```-xml```: extract the xml information only for each image, xml information includes:
		  - one <sample>.Parameters.xml: sample location, shape, and scale
		  - one <sample>.Full.xml: the full xml of an im3 without the bitmap
		  - a .SpectralBasisInfo.Exposure.xml for each image containing the exposure times of the image
- To "inject" a directory of .dat binary blobs for each image back into the directory of im3s use:
  - ```ConvertIm3Path -<base> -<FWpath> -<SlideID> -i```
  - Exports the new '.im3s' into the ```<flatw_im3_path>``` directory
