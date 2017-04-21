//Slice 2013

#include "Platform.h"

#ifndef DEBUG_ALL
#define DEBUG_EDID 1
#else
#define DEBUG_EDID DEBUG_ALL
#endif

#if DEBUG_SET == 0
#define DBG(...)
#else
#define DBG(...) DebugLog(DEBUG_EDID, __VA_ARGS__)
#endif

EFI_STATUS EFIAPI GetEdidImpl(
                              IN  EFI_EDID_OVERRIDE_PROTOCOL          *This,
                              IN  EFI_HANDLE                          *ChildHandle,
                              OUT UINT32                              *Attributes,
                              IN OUT UINTN                            *EdidSize,
                              IN OUT UINT8                            **Edid
                              )
{
  *Edid = gSettings.CustomEDID;
  *EdidSize = 128;
  *Attributes = 0;
  if (*Edid) {
    return EFI_SUCCESS;
  }
  return EFI_NOT_FOUND;
}

EFI_EDID_OVERRIDE_PROTOCOL gEdidOverride =
{
  GetEdidImpl
};

EFI_STATUS
InitializeEdidOverride ()
{
  EFI_STATUS              Status;
  EFI_EDID_OVERRIDE_PROTOCOL *EdidOverride;

  EdidOverride = AllocateCopyPool(sizeof(EFI_EDID_OVERRIDE_PROTOCOL), &gEdidOverride);
  
  Status = gBS->InstallMultipleProtocolInterfaces (
                                                   &gImageHandle,
                                                   &gEfiEdidOverrideProtocolGuid,
                                                   EdidOverride,
                                                   NULL
                                                   );
  if (EFI_ERROR (Status)) {
    DBG("Can't install EdidOverride on ImageHandle\n");
  }
  return Status;
}

//used only if VBiosPatchNeeded and if no CustomEDID
UINT8* getCurrentEdid (VOID)
{
  EFI_STATUS                      Status;
  EFI_EDID_ACTIVE_PROTOCOL        *EdidProtocol;
  UINT8                           *Edid;
  
  DBG ("EdidActive:");
  Edid = NULL;
  Status = gBS->LocateProtocol (&gEfiEdidActiveProtocolGuid, NULL, (VOID**)&EdidProtocol);
  if (!EFI_ERROR (Status)) {
    DBG(" size=%d", EdidProtocol->SizeOfEdid);
    if (EdidProtocol->SizeOfEdid > 0) {
      Edid = AllocateCopyPool (EdidProtocol->SizeOfEdid, EdidProtocol->Edid);
    }
  }
  DBG(" %a\n", Edid != NULL ? "found" : "not found");
  
  return Edid;
}

// EDID code was rewritten by Sherlocks
EFI_STATUS GetEdidDiscovered(VOID)
{
	EFI_STATUS						Status;
	UINTN i, j;
  UINTN N;
  gEDID       = NULL;
  
	Status = gBS->LocateProtocol (&gEfiEdidDiscoveredProtocolGuid, NULL, (VOID **)&EdidDiscovered);
  
	if (!EFI_ERROR (Status)) {
    N = EdidDiscovered->SizeOfEdid;
    if (!GlobalConfig.DebugLog) {
      MsgLog("EdidDiscovered size=%d\n", N);
    }
    if (N == 0) {
			return EFI_NOT_FOUND;
		}
    //gEDID is a place to store Custom of Discovered EDID
    gEDID = AllocateAlignedPages(EFI_SIZE_TO_PAGES(N), 128);
    
    if (gSettings.InjectEDID){
      MsgLog ("Inject EDID\n");
      if (!gSettings.CustomEDID) {
        //MsgLog("  No Custom EDID\n");
        CopyMem(gEDID, EdidDiscovered->Edid, N);
        ((UINT8*)gEDID)[127] = (UINT8)(256 - Checksum8(gEDID, 127));
        gSettings.CustomEDID = gEDID;
        
        if (!GlobalConfig.DebugLog) {
          MsgLog("------- EDID Table\n");
          for (i=0; i<N; i+=10) {
            MsgLog("%03d  |", i);
            for (j=0; j<10; j++) {
              if (i+j > N-1) break;
              MsgLog("  %02x", gEDID[i+j]);
            }
            MsgLog("\n");
          }
        }
        if ((gSettings.VendorEDID) && (gSettings.ProductEDID)){
          ((UINT16*)gEDID)[4] = gSettings.VendorEDID;
          MsgLog("    VendorID = 0x%04lx\n", gSettings.VendorEDID);
          
          ((UINT16*)gEDID)[5] = gSettings.ProductEDID;
          MsgLog("    ProductID = 0x%04lx\n", gSettings.ProductEDID);
          
          ((UINT8*)gEDID)[127] = (UINT8)(256 - Checksum8(gEDID, 127));
          gSettings.CustomEDID = gEDID;
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        else if (gSettings.VendorEDID) {
          ((UINT16*)gEDID)[4] = gSettings.VendorEDID;
          MsgLog("    VendorID = 0x%04lx\n", gSettings.VendorEDID);
          
          ((UINT8*)gEDID)[127] = (UINT8)(256 - Checksum8(gEDID, 127));
          gSettings.CustomEDID = gEDID;
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        else if (gSettings.ProductEDID) {
          ((UINT16*)gEDID)[5] = gSettings.ProductEDID;
          MsgLog("    ProductID = 0x%04lx\n", gSettings.ProductEDID);
          
          ((UINT8*)gEDID)[127] = (UINT8)(256 - Checksum8(gEDID, 127));
          gSettings.CustomEDID = gEDID;
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
      }
      else if (gSettings.CustomEDID) {
        MsgLog("  Use Custom EDID\n");
        
        if ((UINT8)gSettings.CustomEDID[127] == (UINT8)(256 - Checksum8(gSettings.CustomEDID, 127))){
          //MsgLog("    Custom EDID Checksum is ok\n");
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- Custom EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gSettings.CustomEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        else {
          MsgLog("    Custom EDID Checksum = %02x\n", (UINT8)gSettings.CustomEDID[127]);
          MsgLog("    Custom EDID Checksum is wrong\n");
          
          ((UINT8*)gSettings.CustomEDID)[127] = (UINT8)(256 - Checksum8(gSettings.CustomEDID, 127));
          MsgLog("    Fixed Custom EDID Checksum = %02x\n", (UINT8)gSettings.CustomEDID[127]);
          //MsgLog("    Custom EDID Checksum is ok\n");
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- Custom EDID Table with fixed Checksum\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gSettings.CustomEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        if ((gSettings.VendorEDID) && (gSettings.ProductEDID)) {
          ((UINT16*)gSettings.CustomEDID)[4] = gSettings.VendorEDID;
          MsgLog("    VendorID = 0x%04lx\n", gSettings.VendorEDID);
          
          ((UINT16*)gSettings.CustomEDID)[5] = gSettings.ProductEDID;
          MsgLog("    ProductID = 0x%04lx\n", gSettings.ProductEDID);
          
          ((UINT8*)gSettings.CustomEDID)[127] = (UINT8)(256 - Checksum8(gSettings.CustomEDID, 127));
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New Custom EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gSettings.CustomEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        else if (gSettings.VendorEDID) {
          ((UINT16*)gSettings.CustomEDID)[4] = gSettings.VendorEDID;
          MsgLog("    VendorID = 0x%04lx\n", gSettings.VendorEDID);
          
          ((UINT8*)gSettings.CustomEDID)[127] = (UINT8)(256 - Checksum8(gSettings.CustomEDID, 127));
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New Custom EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gSettings.CustomEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
        else if (gSettings.ProductEDID) {
          ((UINT16*)gSettings.CustomEDID)[5] = gSettings.ProductEDID;
          MsgLog("    ProductID = 0x%04lx\n", gSettings.ProductEDID);
          
          ((UINT8*)gSettings.CustomEDID)[127] = (UINT8)(256 - Checksum8(gSettings.CustomEDID, 127));
          
          if (!GlobalConfig.DebugLog) {
            MsgLog("------- New Custom EDID Table\n");
            for (i=0; i<N; i+=10) {
              MsgLog("%03d  |", i);
              for (j=0; j<10; j++) {
                if (i+j > N-1) break;
                MsgLog("  %02x", gSettings.CustomEDID[i+j]);
              }
              MsgLog("\n");
            }
          }
        }
      }
    }
    else{
      //MsgLog ("Not Inject EDID\n");
      CopyMem(gEDID, EdidDiscovered->Edid, N);
      ((UINT8*)gEDID)[127] = (UINT8)(256 - Checksum8(gEDID, 127));
      gSettings.CustomEDID = gEDID;
      
      if (!GlobalConfig.DebugLog) {
        MsgLog("------- EDID Table\n");
        for (i=0; i<N; i+=10) {
          MsgLog("%03d  |", i);
          for (j=0; j<10; j++) {
            if (i+j > N-1) break;
            MsgLog("  %02x", gEDID[i+j]);
          }
          MsgLog("\n");
        }
      }
    }
  }
  return Status;
}


