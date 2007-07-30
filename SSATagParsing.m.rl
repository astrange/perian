/*
 *  SSARenderCodec.m
 *  Copyright (c) 2007 Perian Project
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; 
 *  version 2.1 of the License.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#import "SSATagParsing.h"
#import "Categories.h"

@implementation SSAStyleSpan
-(void)dealloc
{
	ATSUDisposeStyle(astyle);
	[super dealloc];
}
@end

@implementation SSARenderEntity
-(void)dealloc
{
	int i;
	for (i=0; i < style_count; i++) [styles[i] release];
	if (disposelayout) ATSUDisposeTextLayout(layout);
	free(text);
	free(styles);
	[nstext release];
	[super dealloc];
}

-(void)increasestyles
{
	style_count++;
	styles = realloc(styles, sizeof(SSAStyleSpan*[style_count]));
}

-(NSString*)description
{
	return [NSString stringWithFormat:@"\"%@\", %d styles, %@", nstext, style_count,
		   (posx != 1) ? [NSString stringWithFormat:@"pos (%d,%d)",posx,posy] : [NSString stringWithFormat:@"h %d v %d", halign, valign]];
}
@end

%% machine SSAtag;
%% write data;

void SetATSUStyleFlag(ATSUStyle style, ATSUAttributeTag t, Boolean v)
{
	ATSUAttributeTag tags[] = {t};
	ByteCount		 sizes[] = {sizeof(v)};
	ATSUAttributeValuePtr vals[] = {&v};
	
	ATSUSetAttributes(style,1,tags,sizes,vals);
}

void SetATSUStyleOther(ATSUStyle style, ATSUAttributeTag t, ByteCount s, const ATSUAttributeValuePtr v)
{
	ATSUAttributeTag tags[] = {t};
	ByteCount		 sizes[] = {s};
	ATSUAttributeValuePtr vals[] = {v};
	
	ATSUSetAttributes(style,1,tags,sizes,vals);
}

void SetATSULayoutOther(ATSUTextLayout l, ATSUAttributeTag t, ByteCount s, const ATSUAttributeValuePtr v)
{
	ATSUAttributeTag tags[] = {t};
	ByteCount		 sizes[] = {s};
	ATSUAttributeValuePtr vals[] = {v};
	
	ATSUSetLayoutControls(l,1,tags,sizes,vals);
}

static ATSURGBAlphaColor ParseColorTag(unsigned long c, float a)
{
	unsigned char r,g,b;
	r = c & 0xff;
	g = (c >> 8) & 0xff;
	b = (c >> 16) & 0xff;
	
	return (ATSURGBAlphaColor){r/255.,g/255.,b/255.,a};
}

static void UpdateAlignment(int inum, int cur_posx, int *valign, int *halign, ATSUTextLayout cur_layout)
{
	int cur_halign, cur_valign;
	
	switch (inum) {
		case 1: case 4: case 7: cur_halign = S_LeftAlign; break;
		case 2: case 5: case 8: default: cur_halign = S_CenterAlign; break;
		case 3: case 6: case 9: cur_halign = S_RightAlign;
	}
	
	switch (inum) {
		case 1: case 2: case 3: default: cur_valign = S_BottomAlign; break; 
		case 4: case 5: case 6: cur_valign = S_MiddleAlign; break; 
		case 7: case 8: case 9: cur_valign = S_TopAlign;
	}
	
	*halign = cur_halign;
	*valign = cur_valign;
	Fract alignment;
	
	switch(cur_halign) {
		case S_LeftAlign:
			alignment = FloatToFract(0.);
			break;
		case S_CenterAlign: default:
			alignment = kATSUCenterAlignment;  
			break;
		case S_RightAlign: 
			alignment = FloatToFract(1.);
	}
	SetATSULayoutOther(cur_layout, kATSULineFlushFactorTag, sizeof(Fract), &alignment);
}

NSArray *ParseSubPacket(NSString *str, SSADocument *ssa, Boolean plaintext)
{
	NSArray *linea;
	int i=0, j, pcount = 1; unsigned len;
	NSMutableArray *rentities = [NSMutableArray array];
	
	if (plaintext) {
		linea = [NSArray arrayWithObject:str];
	} else {
		linea =  [str componentsSeparatedByString:@"\n"];
		pcount = [linea count];
	}

	for (; i < pcount; i ++) {
		SSARenderEntity *re = [[[SSARenderEntity alloc] init] autorelease];
		BOOL ldirty = NO;
		
		if (plaintext) {
			re->style = ssa->defaultstyle;
			re->layout = re->style->layout;
			re->layer = 0;
			re->marginl = re->style->marginl;
			re->marginr = re->style->marginl;
			re->marginv = re->style->marginl;
			re->usablewidth = re->style->usablewidth;
			re->halign = 1;
			re->valign = 0;
			re->nstext = [linea objectAtIndex:i];
			re->styles = NULL;
			re->disposelayout = NO;
		} else {
			NSArray *ar = STSplitStringWithCount([linea objectAtIndex:(ssa->collisiontype == NormalCollisions) ? i : (pcount - i - 1)],@",",9);

			if ([ar count] < 9) continue;
			
			re->layer = [[ar objectAtIndex:1] intValue];
			NSString *sn = [ar objectAtIndex:2];
			
			re->style = ssa->defaultstyle;
			
			for (j=0; j < ssa->stylecount; j++) {
				if ([sn isEqualToString:ssa->styles[j].name])  {
					re->style = &ssa->styles[j]; 
					break;
				}
			}

			re->marginl = [[ar objectAtIndex:5] intValue];
			re->marginr = [[ar objectAtIndex:6] intValue];
			re->marginv = [[ar objectAtIndex:7] intValue];
			
			if (re->marginl == 0) re->marginl = re->style->marginl; else ldirty = TRUE;
			if (re->marginr == 0) re->marginr = re->style->marginr; else ldirty = TRUE;
			if (re->marginv == 0) re->marginv = re->style->marginv; else ldirty = TRUE;
			
			if (ldirty) {
				ATSUTextMeasurement width;
				ATSUAttributeTag tag[] = {kATSULineWidthTag};
				ByteCount		 size[] = {sizeof(ATSUTextMeasurement)};
				ATSUAttributeValuePtr val[] = {&width};
				
				re->usablewidth = ssa->resX - re->marginl - re->marginr; 
				ATSUCreateAndCopyTextLayout(re->style->layout,&re->layout);
				width = IntToFixed(re->usablewidth);
				
				ATSUSetLayoutControls(re->layout,1,tag,size,val);
				re->disposelayout = YES;
			} else {
				re->usablewidth = re->style->usablewidth;
				re->layout = re->style->layout;
				re->disposelayout = NO;
			}
			
			re->nstext = [ar objectAtIndex:8];
		}
		len = [re->nstext length];
		re->text = malloc(sizeof(unichar[len]));
		
		[re->nstext getCharacters:re->text];
			
		re->style_count = 0;
		re->posx = re->posy = -1;
		re->halign = re->style->halign;
		re->valign = re->style->valign;
		re->multipart_drawing=NO;
		re->is_shape=NO;
		
#define end_re \
		cur_range = (NSRange){strbegin - pb, p - strbegin};\
		cur_range.location -= outputoffset;\
		cur_range.length -= lengthreduce;\
		if (cur_range.length) {[re increasestyles];\
		re->styles[re->style_count-1] = [[SSAStyleSpan alloc] init];\
		re->styles[re->style_count-1]->outline = cur_outline;\
		re->styles[re->style_count-1]->shadow = cur_shadow;\
		re->styles[re->style_count-1]->angle = cur_frz;\
		re->styles[re->style_count-1]->astyle = cur_style;\
		re->styles[re->style_count-1]->range = cur_range;\
		re->styles[re->style_count-1]->outlineblur = cur_be;\
		re->styles[re->style_count-1]->color = cur_color;}\
		parsetmp = [NSString stringWithCharacters:skipbegin length:p-skipbegin];\
		[output appendString:parsetmp]; \
		re->nstext = dtmp = output;\
		re->text = malloc(sizeof(unichar[[re->nstext length]]));\
		[re->nstext getCharacters:re->text];\
		[re->nstext retain];
		
		{
			NSRange cur_range = {0,0};
			ATSUStyle cur_style;
			ATSUTextLayout cur_layout;
			NSMutableString *output = [NSMutableString string], *dtmp;
			unichar *p = re->text, *pe = &re->text[len], *numbegin = p, *strbegin = p, *skipbegin = p, *intbegin = p, *pb = p, *posbegin=p, *strparambegin=p;
			float num = 0, cur_outline = re->style->outline, cur_shadow = re->style->shadow, cur_scalex = re->style->scalex, cur_scaley = re->style->scaley, cur_frz=re->style->angle;
			NSString *parsetmp;
			int cs, cur_valign=re->valign, cur_halign=re->halign, cur_posx=-1, cur_posy=-1;
			ssacolors cur_color = re->style->color;
			CGAffineTransform matrix;
			
			unsigned long inum=0;
			unsigned outputoffset=0, lengthreduce=0;
			BOOL flag=0, newLayout=FALSE, cur_be = FALSE;
			Fixed fixv;
			
			ATSUCreateAndCopyStyle(re->style->atsustyle,&cur_style);
			
			%%{
				alphtype unsigned short;
				
				action bold {SetATSUStyleFlag(cur_style, kATSUQDBoldfaceTag, flag);}
				
				action italic {SetATSUStyleFlag(cur_style, kATSUQDItalicTag, flag);}
				
				action uline {SetATSUStyleFlag(cur_style, kATSUQDUnderlineTag, flag);}
				
				action strike {SetATSUStyleFlag(cur_style, kATSUStyleStrikeThroughTag, flag);}
				
				action bordersize {cur_outline = num; re->multipart_drawing = YES;}
				
				action shadowsize {cur_shadow = num; re->multipart_drawing = YES;}
				
				action bluredge {cur_be = flag;}
				
				action frot {cur_frz = num; re->multipart_drawing = YES;}
				
				action fsize {
					num *= (72./96.); // scale from Windows 96dpi
					fixv = FloatToFixed(num);
					SetATSUStyleOther(cur_style, kATSUSizeTag, sizeof(fixv), &fixv);
				}
				
				action ftrack {
					fixv = FloatToFixed(num);
					SetATSUStyleOther(cur_style, kATSUTrackingTag, sizeof(fixv), &fixv);
				}
				
				action fscalex {
					cur_scalex = num;
					matrix = CGAffineTransformMakeScale(cur_scalex/100.,cur_scaley/100.);		
					SetATSUStyleOther(cur_style, kATSUFontMatrixTag, sizeof(matrix), &matrix);
				}
				
				action fscaley {
					cur_scaley = num;
					matrix = CGAffineTransformMakeScale(cur_scalex/100.,cur_scaley/100.);	
					SetATSUStyleOther(cur_style, kATSUFontMatrixTag, sizeof(matrix), &matrix);
				}
				
				action strp_begin {
					strparambegin = p;
				}
				
				action fontname {
					ATSUFontID	font;
					font = FMGetFontFromATSFontRef(ATSFontFindFromName((CFStringRef)[NSString stringWithCharacters:strparambegin length:p-strparambegin],kATSOptionFlagsDefault));
					SetATSUStyleOther(cur_style, kATSUFontTag, sizeof(ATSUFontID), &font);
				}
				
				action alignment {
					if (!newLayout) {
						newLayout = TRUE;
						ATSUCreateAndCopyTextLayout(re->layout,&cur_layout);
					}
					
					UpdateAlignment(inum, cur_posx, &cur_valign, &cur_halign, cur_layout);
				}

				action ssa_alignment {
					if (!newLayout) {
						newLayout = TRUE;
						ATSUCreateAndCopyTextLayout(re->layout,&cur_layout);
					}

					UpdateAlignment(SSA2ASSAlignment(inum), cur_posx, &cur_valign, &cur_halign, cur_layout);
				}
				
				action pos_begin {
					posbegin=p;
				}
				
				action pos_end {
					if (!newLayout) {
						newLayout = TRUE;
						ATSUCreateAndCopyTextLayout(re->layout,&cur_layout);
					}
					NSArray *coo = [[NSString stringWithCharacters:posbegin length:p-posbegin] componentsSeparatedByString:@","];
					cur_posx = [[coo objectAtIndex:0] intValue];
					cur_posy = [[coo objectAtIndex:1] intValue];
				}
				
				action primarycolor {
					cur_color.primary = ParseColorTag(inum,cur_color.primary.alpha);
					re->multipart_drawing = YES;
				}
				
				action secondarycolor {
					cur_color.secondary = ParseColorTag(inum,cur_color.secondary.alpha);
					re->multipart_drawing = YES;
				}
				
				action outlinecolor {
					cur_color.outline = ParseColorTag(inum,cur_color.outline.alpha);
					re->multipart_drawing = YES;
				}
				
				action shadowcolor {
					cur_color.shadow = ParseColorTag(inum,cur_color.shadow.alpha);
					re->multipart_drawing = YES;
				}
				
				action primaryalpha {
					cur_color.primary.alpha = (255 - inum) / 255.f;
					re->multipart_drawing = YES;
				}
				
				action secondaryalpha {
					cur_color.secondary.alpha = (255 - inum) / 255.f;
					re->multipart_drawing = YES;
				}
				
				action outlinealpha {
					cur_color.outline.alpha = (255 - inum) / 255.f;
					re->multipart_drawing = YES;
				}
				
				action shadowalpha {
					cur_color.shadow.alpha = (255 - inum) / 255.f;
					re->multipart_drawing = YES;
				}
				
				action nl_handler {
					NSString *append = @"\n";
					parsetmp = [NSString stringWithCharacters:skipbegin length:(p-2)-skipbegin];
					[output appendString:parsetmp];
					
					skipbegin = p;

					if (*(p - 1) == 'h') append = @" ";
                    
					[output appendString:append];
					
					lengthreduce++;
				}
				
				action enter_tag {
					unsigned taglen = p - skipbegin;
					parsetmp = [NSString stringWithCharacters:skipbegin length:taglen];
					[output appendString:parsetmp];
					skipbegin = p;
					
					cur_range = (NSRange){strbegin - pb, p - strbegin};
					cur_range.location -= outputoffset;
					cur_range.length -= lengthreduce;
					
					outputoffset += lengthreduce;
					lengthreduce = 0;
                    
                    if (cur_range.length) {
                        [re increasestyles];
                        re->styles[re->style_count-1] = [[SSAStyleSpan alloc] init];
                        re->styles[re->style_count-1]->outline = cur_outline;
                        re->styles[re->style_count-1]->shadow = cur_shadow;
                        re->styles[re->style_count-1]->angle = cur_frz;
                        re->styles[re->style_count-1]->astyle = cur_style;
                        re->styles[re->style_count-1]->range = cur_range;
                        re->styles[re->style_count-1]->outlineblur = cur_be;
                        re->styles[re->style_count-1]->color = cur_color;
                        ATSUCreateAndCopyStyle(cur_style,&cur_style);
                    }
				}
				
				action exit_tag {
					p++; // exit_tag uses > rather than % because ragel ordering is opposite of what we want
					
					outputoffset += p - skipbegin;
					skipbegin = p;
					strbegin = p;

					if (newLayout) {
						newLayout = FALSE;
						end_re;
                        
						if ([re->nstext length] != 0) [rentities addObject:re];
						
						SSARenderEntity *nre = [[[SSARenderEntity alloc] init] autorelease];
						nre->layer = re->layer;
						nre->style = re->style;
						nre->marginl = re->marginl; nre->marginr = re->marginr; nre->marginv = re->marginv; nre->usablewidth = re->usablewidth;
						nre->posx = cur_posx; nre->posy = cur_posy; nre->halign = cur_halign; nre->valign = cur_valign;
						nre->nstext = nil;
						nre->text = nil;
						nre->layout = cur_layout;
						nre->styles = malloc(0);
						nre->style_count = 0;
						nre->disposelayout = YES;
						nre->multipart_drawing = NO;
						nre->is_shape = re->is_shape;
						re = nre;
					}
					
					p--;
				}
				
				action color_end {
					NSString *hexn = [NSString stringWithCharacters:intbegin length:p-intbegin];
					inum = strtoul([hexn UTF8String], NULL, 16);
				}
				
				action styleset {
					re->multipart_drawing = YES;
					ssastyleline *the_style = re->style;
					NSString *searchsn = [NSString stringWithCharacters:strparambegin length:p-strparambegin];
					
					if ([searchsn length] > 0) {
						for (j=0; j < ssa->stylecount; j++) {
							if ([searchsn isEqualToString:ssa->styles[j].name])  {
								the_style = &ssa->styles[j]; 
								break;
							}
						}
					}
					
					ATSUCopyAttributes(the_style->atsustyle,cur_style);
					cur_color = the_style->color;
					cur_outline = the_style->outline;
					cur_shadow = the_style->shadow;
					cur_frz = the_style->angle;
					cur_scalex = cur_scaley = 1;
				}
				
				action skip_t_tag {
					while (p != pe && *p != ')' && *p != '}') p++;
					p++;
				}
				
				action draw_mode {
					re->is_shape = inum != 0;
				}
				
				flag = ([01] % {unichar fl = *(p-1); if (fl == '0' || fl == '1') flag = fl - '0';})? > {flag = 0;};
				num_ = "-"? digit+ ('.' digit*)?;
				num = num_ > {numbegin = p;} % {num = [[NSString stringWithCharacters:numbegin length:p-numbegin] doubleValue];};
				
				intnum = "-"? (digit+) > {intbegin = p;} % {inum = [[NSString stringWithCharacters:intbegin length:p-intbegin] intValue];};
				
				color = ("H"|"&"){,2} (xdigit+) > {intbegin = p;} % color_end "&";

				cmd_specific = (("pos(" [^)]+ > pos_begin ")" % pos_end)
								|"bord" num %bordersize
								|"b" flag %bold 
								|"be" flag %bluredge
								|"i" flag %italic 
								|"u" flag %uline
								|"s" flag %strike
								|"fs" num %fsize 
								|"fsp" num %ftrack
								|"fscx" num %fscalex
								|"fscy" num %fscaley
								|("fr" "z"? num %frot) 
								|("fn" [^\\}]* > strp_begin %fontname) 
								|"shad" num %shadowsize
								|"a" intnum %ssa_alignment
								|"an" intnum %alignment
								|"c" color %primarycolor
								|"1c" color %primarycolor
								|"2c" color %secondarycolor
								|"3c" color %outlinecolor
								|"4c" color %shadowcolor
								|("1a"|"alpha") color %primaryalpha
								|"2a" color %secondaryalpha
								|"3a" color %outlinealpha
								|"4a" color %shadowalpha
								|("r" [^\\}]* > strp_begin %styleset)
								|("fe"|"k"|"kf"|"K"|"ko"|"q"|"fr"|"fad"|"move"|"clip"|"o"|"frx"|"fry") [^\\}]*
								|"p" num %draw_mode
								#|"t" [^)}]* # enabling this causes ragel to malloc forever
								|"t(" % skip_t_tag
								|""
								);
				
				cmd = ("\\" :> cmd_specific)+;
				
				plaintext = [^}]*;

				tag = "{" > enter_tag (cmd | plaintext) "}" > exit_tag;
				
				nl = "\\" [Nnh];
				
				special = (nl % nl_handler %/ nl_handler) | tag;
								
				text = any*;
				main := (text special?)*;
			}%%
				
			%%write init;
			%%write exec;
			%%write eof;
			
			end_re;
			if (!cur_range.length) ATSUDisposeStyle(cur_style);

			free(pb);
			if ([re->nstext length]) [rentities addObject:re];
		}
		
	}
	return rentities;
}
